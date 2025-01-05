from flask import Flask, render_template, jsonify, request, url_for, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import psutil
import numpy as np
import os
import socket  # Added to get hostname

# Initialize Flask app with explicit template and static folders
app = Flask(__name__, 
    template_folder=os.path.abspath('templates'),
    static_folder=os.path.abspath('static'))

# Prometheus metrics
REQUESTS = Counter('requests_total', 'Total requests')
LATENCY = Histogram('request_latency_seconds', 'Request latency in seconds')

# Global variables for load simulation
request_count = 0
MEMORY_GROWTH_FACTOR = 5  # MB per request
memory_cache = []

# Simulated product database
products = [
    {
        "id": 1, 
        "name": "Laptop", 
        "price": 999.99, 
        "image": "laptop.jpg",
        "description": "High-performance laptop with the latest processor and ample storage.",
        "specs": {
            "Processor": "Intel Core i7",
            "RAM": "16GB",
            "Storage": "512GB SSD",
            "Display": "15.6 inch Full HD",
            "Battery": "Up to 10 hours"
        }
    },
    {
        "id": 2, 
        "name": "Smartphone", 
        "price": 499.99, 
        "image": "smartphone.jpg",
        "description": "Feature-packed smartphone with an excellent camera and long-lasting battery.",
        "specs": {
            "Screen": "6.5 inch OLED",
            "Camera": "Triple lens 48MP",
            "Processor": "Snapdragon 888",
            "Storage": "128GB",
            "Battery": "4500mAh"
        }
    },
    {
        "id": 3, 
        "name": "Headphones", 
        "price": 99.99, 
        "image": "headphones.jpg",
        "description": "Wireless over-ear headphones with noise cancellation for immersive audio experience.",
        "specs": {
            "Type": "Over-ear",
            "Wireless": "Yes, Bluetooth 5.0",
            "Battery Life": "Up to 30 hours",
            "Noise Cancellation": "Active",
            "Weight": "250g"
        }
    },
    {
        "id": 4, 
        "name": "Smartwatch", 
        "price": 199.99, 
        "image": "smartwatch.jpg",
        "description": "Fitness-focused smartwatch with heart rate monitoring and GPS tracking.",
        "specs": {
            "Display": "1.4 inch AMOLED",
            "Water Resistance": "5 ATM",
            "GPS": "Built-in",
            "Battery": "Up to 7 days",
            "Compatibility": "iOS and Android"
        }
    },
    {
        "id": 5, 
        "name": "Tablet", 
        "price": 299.99, 
        "image": "tablet.jpg",
        "description": "Versatile tablet perfect for work and entertainment on-the-go.",
        "specs": {
            "Screen": "10.2 inch Retina display",
            "Processor": "A13 Bionic chip",
            "Storage": "64GB",
            "Camera": "8MP back, 12MP front",
            "Battery": "Up to 10 hours"
        }
    },
]

# Get the hostname of the pod
hostname = socket.gethostname()

def check_item_availability(product_id):
    return any(product['id'] == product_id for product in products)
    
@app.route('/')
@LATENCY.time()
def home():
    REQUESTS.inc()
    app.logger.info("Accessing home page")
    return render_template('index.html', products=products)

@app.route('/product/<int:product_id>')
@LATENCY.time()
def product_detail(product_id):
    REQUESTS.inc()
    app.logger.info(f"Accessing product {product_id}")
    product = next((p for p in products if p['id'] == product_id), None)
    if product:
        is_available = check_item_availability(product_id)
        return render_template('product.html', product=product, is_available=is_available)
    return "Product not found", 404

@app.route('/api/check_availability/<int:product_id>')
@LATENCY.time()
def api_check_availability(product_id):
    REQUESTS.inc()
    app.logger.info(f"Checking availability for product {product_id}")
    is_available = check_item_availability(product_id)
    response = {
        "product_id": product_id,
        "available": is_available,
        "instance_id": hostname  # Include the instance ID
    }
    return jsonify(response)

@app.route('/api/products')
@LATENCY.time()
def get_products():
    REQUESTS.inc()
    app.logger.info("Accessing products API")
    return jsonify(products)

@app.route('/api/podName')
@LATENCY.time()
def get_pod_name():
    return hostname, 200

@app.route('/healthz')
def healthz():
    return 'OK', 200

if __name__ == '__main__':
    # Add debug logging
    app.logger.setLevel('INFO')
    app.run(host='0.0.0.0', port=5000, debug=True)
