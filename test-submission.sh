# Default values
timeout=300
skip_create_cluster=false
cluster_name=test-submission

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --timeout) timeout="$2"; shift ;;
        --skip-create-cluster) skip_create_cluster=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ "$skip_create_cluster" = false ]; then
  echo "Creating a new KIND cluster"
  # check if KIND cluster already exists
  kind get clusters | grep -q $cluster_name
  if [ $? -eq 0 ]; then
    echo "kind cluster named $cluster_name already exists, please delete it before running this script"
    exit 1
  else
    echo "creating kind cluster"
    kind create cluster --name $cluster_name --config ./kind-config.yaml
  fi
fi

set -e

# Build the Docker images
pet_store1_image_name=$(yq eval '.spec.template.spec.containers[0].image' ./multi-service-app/pet-store/deployment1.yaml)
pet_store2_image_name=$(yq eval '.spec.template.spec.containers[0].image' ./multi-service-app/pet-store/deployment2.yaml)
pet_order_image_name=$(yq eval '.spec.template.spec.containers[0].image' ./multi-service-app/pet-order/deployment.yaml)

if [[ "$pet_store1_image_name" = "null" || "$pet_store2_image_name" = "null" || "$pet_order_image_name" == "null" ]]; then
    echo "Error: failed to get the image name of the pet-store or pet-order services. Please check the deployment.yaml files."
    exit 1
fi

# Build pet-store1 image
echo "building the pet-store1 docker image with the following tag:" $pet_store1_image_name
docker build -f ./multi-service-app/pet-store/Dockerfile -t $pet_store1_image_name ./multi-service-app

# Build pet-store2 image if it's different from pet-store1
if [[ "$pet_store1_image_name" != "$pet_store2_image_name" ]]; then
    echo "building the pet-store2 docker image with the following tag:" $pet_store2_image_name
    docker build -f ./multi-service-app/pet-store/Dockerfile2 -t $pet_store2_image_name ./multi-service-app
else
    echo "pet-store2 uses the same image as pet-store1, skipping duplicate build"
fi

echo "building the pet-order docker image with the following tag:" $pet_order_image_name
docker build -f ./multi-service-app/pet-order/Dockerfile -t $pet_order_image_name ./multi-service-app

# Load the Docker images into the KIND cluster
kind load docker-image $pet_store1_image_name --name $cluster_name
if [[ "$pet_store1_image_name" != "$pet_store2_image_name" ]]; then
    kind load docker-image $pet_store2_image_name --name $cluster_name
fi
kind load docker-image $pet_order_image_name --name $cluster_name

# Function to wait for all pods to be in Running state
function wait_for_all_pods_running() {
  local timeout=$1
  local interval=5 # Check every 5 seconds.
  local elapsed=0

  function check_pods_running() {
    # Get the count of pods that are NOT in the 'Running' or 'Succeeded' state.
    not_running_count=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | \
      grep -v -E '\s+(Running|Completed)\s+' | wc -l)

    echo "Pods not in 'Running' or 'Completed' state: $not_running_count"

    if [ "$not_running_count" -gt 0 ]; then
      echo "Non-running pods:"
      kubectl get pods --all-namespaces --no-headers 2>/dev/null | \
        grep -v -E '\s+(Running|Completed)\s+'
    fi

    if [ "$not_running_count" -eq 0 ]; then
      return 0 # All pods are running.
    else
      return 1 # There are pods not in the 'Running' state.
    fi
  }

  local all_pods_running=false
  while [ "$elapsed" -lt "$timeout" ]; do
    if check_pods_running; then
      echo "All pods are in the 'Running' state."
      all_pods_running=true
      break
    fi
    echo "Waiting for all pods to be in the 'Running' state..."
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  if [ "$all_pods_running" = false ]; then
    echo "Timed out waiting for all pods to be in the 'Running' state."
    return 1
  fi
  
  return 0
}

# Create the namespace
kubectl apply -f ./multi-service-app/namespace.yaml

# Deploy the database
kubectl apply -f ./multi-service-app/database/

# wait for the pod to be created
sleep 10
# Wait for database pods to be running before proceeding
wait_for_all_pods_running "$timeout"
if [ $? -ne 0 ]; then
  exit 1
fi

# Deploy nginx
kubectl apply -f ./multi-service-app/nginx/

# Deploy the pet-store service
kubectl apply -f ./multi-service-app/pet-store/

# Deploy the pet-order service
kubectl apply -f ./multi-service-app/pet-order/

sleep 10

# Wait for all pods to be running
wait_for_all_pods_running "$timeout"
if [ $? -ne 0 ]; then
  exit 1
fi

# Check that the pet-store services are working
urls=("http://localhost:80/pet-types1" "http://localhost:80/pet-types2")
for url in "${urls[@]}"; do
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$url")

    # Check the response status code is 200
    if [[ "$http_status" == "200" ]]; then
        echo "The sanity test for $url passed successfully."
    else
        echo "It seems that the following URL is not working as expected. Please verify it before submitting your assignment"
        echo "URL: $url"
        echo "HTTP Status: $http_status"
        exit 1
    fi
done

# Check that the pet-order service is working
url="http://localhost/transactions"
http_status=$(curl -s -o /dev/null -w "%{http_code}" \
    --request GET \
    --url "$url" \
    --header 'content-type: application/json' \
    --header 'ownerpc: LovesPetsL2M3n4' \
    --data '{
  "type": "Poodle"
}')

# Check the response status code is 200
if [[ "$http_status" == "200" ]]; then
    echo "The sanity test for $url passed successfully."
else
    echo "It seems that the following URL is not working as expected. Please verify it before submitting your assignment"
    echo "URL: $url"
    echo "HTTP Status: $http_status"
    exit 1
fi
