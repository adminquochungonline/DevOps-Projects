#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-devops-project-06}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-devops-project-06}"
ACR_NAME="${ACR_NAME:-acrdevops06app}"
IMAGE_TAG="${IMAGE_TAG:-2.1.2}"

echo "=========================================="
echo "🚀 Connecting to Azure Kubernetes Service"
echo "Resource Group: $RESOURCE_GROUP"
echo "Cluster: $CLUSTER_NAME"
echo "=========================================="

az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "Applying Kubernetes manifests..."
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Dynamically update the image if IMAGE_TAG or ACR_NAME was passed
IMAGE_FULL_PATH="${ACR_NAME}.azurecr.io/sample_app:${IMAGE_TAG}"
echo "Updating deployment image to: $IMAGE_FULL_PATH"
kubectl set image deployment/sample-app-dep sample-app="$IMAGE_FULL_PATH" -n sample-app || true

echo "Checking rollout status..."
kubectl rollout status deployment/sample-app-dep -n sample-app --timeout=120s

echo "=========================================="
echo "Service status:"
kubectl get svc sample-app-svc -n sample-app
echo "=========================================="
