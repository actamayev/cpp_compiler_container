#!/bin/bash

# cleanup.sh - Script to completely clean Docker environment

echo "🧹 Starting complete Docker cleanup..."

# Environment variables
ECR_URL="481665120319.dkr.ecr.us-east-1.amazonaws.com"
REGION="us-east-1"
IMAGE_NAME="firmware-compiler"

# Clean ECR images
echo "🧹 Cleaning ECR images..."
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URL}

# Remove staging tag
aws ecr batch-delete-image \
    --repository-name ${IMAGE_NAME} \
    --image-ids imageTag=staging 2>/dev/null || echo "No staging image to remove"

# Remove production tag
aws ecr batch-delete-image \
    --repository-name ${IMAGE_NAME} \
    --image-ids imageTag=production 2>/dev/null || echo "No production image to remove"

# Remove latest tag
aws ecr batch-delete-image \
    --repository-name ${IMAGE_NAME} \
    --image-ids imageTag=latest 2>/dev/null || echo "No latest image to remove"

echo "✅ ECR cleanup complete"
echo

# Function to run command and check status
run_cmd() {
   echo "⚙️  $1"
   if eval "$2"; then
       echo "✅ Done: $1"
   else
       echo "⚠️  Note: $1 had no items to remove"
   fi
   echo
}

# Stop all containers
run_cmd "Stopping all containers..." \
   "docker stop \$(docker ps -a -q) 2>/dev/null"

# Remove all containers
run_cmd "Removing all containers..." \
   "docker rm \$(docker ps -a -q) 2>/dev/null"

# Remove all images
run_cmd "Removing all images..." \
   "docker rmi \$(docker images -a -q) 2>/dev/null"

# Remove all volumes
run_cmd "Removing all volumes..." \
   "docker volume rm \$(docker volume ls -q) 2>/dev/null"

# Clean buildx cache
echo "🧹 Cleaning buildx cache..."
docker builder prune -af

# System prune
echo "🗑️  Pruning entire Docker system..."
docker system prune -a --volumes -f
echo "✅ System prune complete"
echo

# Remove PlatformIO cache specifically
run_cmd "Removing PlatformIO cache..." \
   "docker volume rm pio-cache 2>/dev/null"

echo "🎉 Cleanup complete! Your Docker environment is now fresh."
