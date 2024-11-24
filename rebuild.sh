#!/bin/bash

# Function to handle errors
error() {
    echo "Error: $1"
    exit 1
}

IMAGE_NAME="cpp-compiler"  # Consistent image name

# Check if environment argument is provided
if [ "$1" != "local" ] && [ "$1" != "staging" ] && [ "$1" != "production" ]; then
    echo "Usage: $0 [local|staging|production]"
    echo "  local: rebuild local compiler"
    echo "  staging: rebuild and push staging compiler to ECR"
    echo "  production: rebuild and push production compiler to ECR"
    exit 1
fi

case "$1" in
    "local")
        echo "Rebuilding local environment..."
        
        # Stop and remove local container
        docker stop cpp-compiler-instance 2>/dev/null
        docker rm cpp-compiler-instance 2>/dev/null
        
        # Remove old image
        docker rmi ${IMAGE_NAME}:test 2>/dev/null
        
        # Create a named volume for workspace if it doesn't exist
        docker volume create cpp-compiler-workspace || true

        # Rebuild local
        docker build -t ${IMAGE_NAME}:test . || error "Local build failed"
        echo "Local environment updated successfully!"
        ;;
        
    "staging"|"production")
        echo "Rebuilding ${1} environment..."
        
        # Login to ECR
        aws ecr get-login-password --region us-east-1 | \
            docker login --username AWS --password-stdin 481665120319.dkr.ecr.us-east-1.amazonaws.com || \
            error "ECR login failed"
            
        # Build and push
        docker build -t ${IMAGE_NAME}:${1} . || error "${1} build failed"
        docker tag ${IMAGE_NAME}:${1} 481665120319.dkr.ecr.us-east-1.amazonaws.com/${IMAGE_NAME}:${1} || error "${1} tag failed"
        docker push 481665120319.dkr.ecr.us-east-1.amazonaws.com/${IMAGE_NAME}:${1} || error "${1} push failed"
        echo "${1} environment updated successfully!"
        ;;
esac
