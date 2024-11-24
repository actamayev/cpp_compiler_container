#!/bin/bash

# Function to handle errors
error() {
    echo "Error: $1"
    exit 1
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
        docker stop cpp-compiler-instance 2>/dev/null
        docker rm cpp-compiler-instance 2>/dev/null
        
        # Remove old image
        docker rmi cpp-compiler 2>/dev/null
        
        # Rebuild local
        docker build -t cpp-compiler . || error "Local build failed"
        echo "Local environment updated successfully!"
        ;;
        
    "staging")
        echo "Rebuilding staging environment..."
        
        # Login to ECR
        aws ecr get-login-password --region us-east-1 | \
            docker login --username AWS --password-stdin 481665120319.dkr.ecr.us-east-1.amazonaws.com || \
            error "ECR login failed"
            
        # Build and push staging
        docker build -t firmware-compiler:staging . || error "Staging build failed"
        docker tag firmware-compiler:staging 481665120319.dkr.ecr.us-east-1.amazonaws.com/firmware-compiler:staging || error "Staging tag failed"
        docker push 481665120319.dkr.ecr.us-east-1.amazonaws.com/firmware-compiler:staging || error "Staging push failed"
        echo "Staging environment updated successfully!"
        ;;
        
    "production")
        echo "Rebuilding production environment..."
        
        # Login to ECR
        aws ecr get-login-password --region us-east-1 | \
            docker login --username AWS --password-stdin 481665120319.dkr.ecr.us-east-1.amazonaws.com || \
            error "ECR login failed"
            
        # Build and push production
        docker build -t firmware-compiler:production . || error "Production build failed"
        docker tag firmware-compiler:production 481665120319.dkr.ecr.us-east-1.amazonaws.com/firmware-compiler:production || error "Production tag failed"
        docker push 481665120319.dkr.ecr.us-east-1.amazonaws.com/firmware-compiler:production || error "Production push failed"
        echo "Production environment updated successfully!"
        ;;
esac
