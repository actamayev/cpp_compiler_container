#!/bin/bash

CLUSTER="bdr-staging-ecs-ec2-cluster"
SERVICE="staging-firmware-compiler-ec2"

echo "🔄 Forcing new deployment..."
aws ecs update-service \
    --cluster $CLUSTER \
    --service $SERVICE \
    --force-new-deployment > /dev/null

echo "⏳ Waiting for deployment to start..."
sleep 5

echo "📋 Recent events:"
aws ecs describe-services \
    --cluster $CLUSTER \
    --services $SERVICE \
    --query 'services[0].events[0:5]' \
    --output text

echo "👀 Monitoring deployment..."
while true; do
    STATUS=$(aws ecs describe-services \
        --cluster $CLUSTER \
        --services $SERVICE \
        --query 'services[0].deployments[0].rolloutState' \
        --output text)
    
    echo "Deployment status: $STATUS"
    
    if [ "$STATUS" = "COMPLETED" ]; then
        break
    fi
    sleep 5
done

echo "✅ Deployment complete!"

# Get new container ID
sleep 5  # Give it a moment to start
CONTAINER_ID=$(docker ps --filter name=staging-firmware-compiler-ec2 --format "{{.ID}}")

echo "🔍 New container logs:"
docker logs $CONTAINER_ID

echo "🌐 Testing health endpoint:"
curl -s http://localhost:3001/health | jq '.'
