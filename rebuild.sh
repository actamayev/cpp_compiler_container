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
SERVER_PORT=3001  # Define port as a variable for easier management

# Function to ensure ECR repository exists
ensure_ecr_repo() {
    if ! aws ecr describe-repositories --repository-names ${IMAGE_NAME} &>/dev/null; then
        echo "Creating ECR repository ${IMAGE_NAME}..."
        aws ecr create-repository --repository-name ${IMAGE_NAME} || error "Failed to create ECR repository"
    else
        echo "Repository ${IMAGE_NAME} already exists, continuing..."
    fi
}

# Function to wait for server health check
wait_for_server() {
    local retries=0
    local max_retries=30
    echo "Waiting for server to be ready..."
    while [ $retries -lt $max_retries ]; do
        if curl -s http://localhost:${SERVER_PORT}/health > /dev/null; then
            echo "Server is ready!"
            return 0
        fi
        retries=$((retries + 1))
        sleep 1
    done
    error "Server failed to respond after 30 seconds"
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
        docker rmi firmware-compiler:latest 2>/dev/null

        # Create named volumes if they don't exist
        docker volume create cpp-workspace-vol
        docker volume create pio-cache

        # Build image
        docker buildx build \
            --platform linux/amd64 \
            --load \
            -t firmware-compiler:latest \
            --build-arg ENVIRONMENT=local \
            --build-arg SERVER_PORT=${SERVER_PORT} \
            . || error "Local build failed"

        # Run with all necessary mounts and environment variables
        docker run -d \
            --name firmware-compiler-instance \
            --platform linux/amd64 \
            -p ${SERVER_PORT}:${SERVER_PORT} \
            -v "${FIRMWARE_DIR}:/firmware:ro" \
            -v cpp-workspace-vol:/workspace \
            -v pio-cache:/root/.platformio \
            -e FIRMWARE_SOURCE=/firmware \
            -e ENVIRONMENT=local \
            -e SERVER_PORT=${SERVER_PORT} \
            firmware-compiler:latest

        # Wait for server to be ready
        wait_for_server

        # Show container logs
        docker logs firmware-compiler-instance

        echo "Local environment updated successfully!"
        echo "Server is running at http://localhost:${SERVER_PORT}"
        ;;

    "staging"|"production")
        echo "Rebuilding ${1} environment..."

        # Set variables
        CLUSTER_NAME="bdr-${1}-ecs-ec2-cluster"
        SERVICE_NAME="${1}-firmware-compiler-ec2"
        
        # Ensure ECR repository exists
        ensure_ecr_repo

        # Login to ECR
        aws ecr get-login-password --region ${REGION} | \
            docker login --username AWS --password-stdin ${ECR_URL} || \
            error "ECR login failed"

        # Build and push with environment-specific build args
        docker buildx build \
            --platform linux/amd64 \
            --push \
            --build-arg ENVIRONMENT="$1" \
            --build-arg SERVER_PORT=${SERVER_PORT} \
            -t ${ECR_URL}/${IMAGE_NAME}:"${1}" \
            . || error "${1} build failed"

        if [ "$1" = "production" ]; then
            docker buildx build \
                --platform linux/amd64 \
                --push \
                --build-arg ENVIRONMENT=production \
                --build-arg SERVER_PORT=${SERVER_PORT} \
                -t ${ECR_URL}/${IMAGE_NAME}:latest \
                . || error "Failed to push latest tag"
        fi

        echo "Verifying image manifest..."
        docker buildx imagetools inspect ${ECR_URL}/${IMAGE_NAME}:"${1}" || error "Manifest verification failed"

        echo "Setting desired count to 0..."
        # Use temporary file to capture output
        TEMP_OUTPUT=$(mktemp)
        if ! aws ecs update-service \
            --cluster "${CLUSTER_NAME}" \
            --service "${SERVICE_NAME}" \
            --desired-count 0 \
            --region ${REGION} > "$TEMP_OUTPUT" 2>&1; then
            cat "$TEMP_OUTPUT"
            rm "$TEMP_OUTPUT"
            error "Failed to update service count to 0"
        fi
        rm "$TEMP_OUTPUT"

        echo "Waiting for tasks to stop..."
        while true; do
            RUNNING_COUNT=$(aws ecs describe-services \
                --cluster "${CLUSTER_NAME}" \
                --services "${SERVICE_NAME}" \
                --region ${REGION} \
                --query 'services[0].runningCount' \
                --output text)
            
            if [ "$RUNNING_COUNT" = "0" ]; then
                break
            fi
            echo "Still waiting for tasks to stop... ($RUNNING_COUNT running)"
            sleep 5
        done

        echo "Starting new deployment..."
        # Use temporary file for output
        TEMP_OUTPUT=$(mktemp)
        if ! aws ecs update-service \
            --cluster "${CLUSTER_NAME}" \
            --service "${SERVICE_NAME}" \
            --desired-count 1 \
            --force-new-deployment \
            --region ${REGION} > "$TEMP_OUTPUT" 2>&1; then
            cat "$TEMP_OUTPUT"
            rm "$TEMP_OUTPUT"
            error "Failed to start new deployment"
        fi
        rm "$TEMP_OUTPUT"

        echo "Waiting for new task to start..."
        TIMEOUT=60  # 5 minutes (12 * 5 seconds)
        COUNT=0
        while [ $COUNT -lt $TIMEOUT ]; do
            RUNNING_COUNT=$(aws ecs describe-services \
                --cluster "${CLUSTER_NAME}" \
                --services "${SERVICE_NAME}" \
                --region ${REGION} \
                --query 'services[0].runningCount' \
                --output text)

            if [ "$RUNNING_COUNT" = "1" ]; then
                echo "New task is running!"
                break
            fi
            echo "Waiting for new task to start... ($RUNNING_COUNT running)"
            COUNT=$((COUNT + 1))
            sleep 5

            if [ $COUNT -eq $TIMEOUT ]; then
                error "Timeout waiting for new task to start"
            fi
        done

        echo "${1} environment updated and redeployed successfully!"
        ;;
esac
