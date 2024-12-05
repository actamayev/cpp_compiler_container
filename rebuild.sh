#!/bin/bash

# Function to handle errors
error() {
    echo "Error: $1"
    exit 1
}

IMAGE_NAME="firmware-compiler"
FIRMWARE_DIR="/Users/arieltamayev/Documents/PlatformIO/pip-bot-firmware"
ECR_URL="481665120319.dkr.ecr.us-east-1.amazonaws.com"
REGION="us-east-1"

# Function to ensure ECR repository exists
ensure_ecr_repo() {
    aws ecr describe-repositories --repository-names ${IMAGE_NAME} 2>/dev/null || {
        echo "Creating ECR repository ${IMAGE_NAME}..."
        aws ecr create-repository --repository-name ${IMAGE_NAME} || error "Failed to create ECR repository"
    }
}

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
        docker stop firmware-compiler-instance 2>/dev/null
        docker rm firmware-compiler-instance 2>/dev/null

        # Remove old images
        docker rmi firmware-compiler:test 2>/dev/null
        docker rmi firmware-compiler:test-amd64 2>/dev/null

        # Create a named volume for the workspace if it doesn't exist
        docker volume create cpp-workspace-vol

        # Build for AMD64 for consistency with staging/production
        echo "Building AMD64 image for local development..."
        docker buildx build \
            --platform linux/amd64 \
            --load \
            -t firmware-compiler:test-amd64 \
            . || error "Local build failed"

        # Run the container with platform specified
        docker run -d \
            --name firmware-compiler-instance \
            --platform linux/amd64 \
            -v "${FIRMWARE_DIR}:/firmware:ro" \
            -v cpp-workspace-vol:/workspace \
            -e FIRMWARE_SOURCE=/firmware \
            firmware-compiler:test-amd64
        echo "Local environment updated successfully!"
        ;;

    "staging"|"production")
        # For staging/production case:
        echo "Rebuilding ${1} environment..."

        # Login to ECR
        aws ecr get-login-password --region ${REGION} | \
            docker login --username AWS --password-stdin ${ECR_URL} || \
            error "ECR login failed"

        # Build and push AMD64 image
        echo "Building amd64 image..."
        docker buildx build \
            --platform linux/amd64 \
            --push \
            -t ${ECR_URL}/${IMAGE_NAME}:${1} \
            . || error "${1} build failed"

        # Tag as latest if it's production
        if [ "$1" = "production" ]; then
            docker buildx build \
                --platform linux/amd64 \
                --push \
                -t ${ECR_URL}/${IMAGE_NAME}:latest \
                . || error "Failed to push latest tag"
        fi

        echo "Verifying image manifest..."
        docker buildx imagetools inspect ${ECR_URL}/${IMAGE_NAME}:${1} || error "Manifest verification failed"

        echo "${1} environment updated successfully!"
        ;;
esac
