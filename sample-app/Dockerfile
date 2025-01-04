FROM python:3.9-slim

WORKDIR /app

# Install system dependencies for numpy and psutil
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create directories for templates and static files
RUN mkdir -p templates static

# Copy application files
COPY app.py .
COPY templates/* templates/
COPY static/* static/

EXPOSE 5000

CMD ["python", "app.py"]