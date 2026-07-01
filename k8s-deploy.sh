#!/bin/bash

# k8s-deploy.sh
# Deployment script for readme-pagespeed-insights to Kubernetes
# Usage: ./k8s-deploy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Define worker nodes for image importing
WORKERS=("10.18.1.107" "10.18.1.108")
NAME="readme-pagespeed-insights"
IMAGE_NAME="readme-pagespeed-insights:latest"
MANIFEST_PATH="./k8s/deployment.yaml"

echo "--------------------------------------------------"
echo "🚀 Starting deployment for [$NAME]..."
echo "--------------------------------------------------"

# 1. Build Image
echo "📦 Step 1: Building Docker image..."
docker build -t "$IMAGE_NAME" .

# 2. Save & Export Image to Kube containerd on all workers
echo "💾 Step 2: Exporting and importing image to Kubernetes cluster..."
TAR_FILE="/tmp/${NAME}-latest.tar"
docker save "$IMAGE_NAME" -o "$TAR_FILE"

for worker in "${WORKERS[@]}"; do
    echo "   -> Importing to worker node $worker..."
    
    # Check if the IP is local to this host
    is_local=false
    if ip addr | grep -q "$worker"; then
        is_local=true
    fi

    if [ "$is_local" = "true" ] && [ -f "/usr/local/bin/k3s" ]; then
        # Local node import
        /usr/local/bin/k3s ctr --namespace k8s.io images import "$TAR_FILE"
    else
        # Remote worker node import
        scp -o StrictHostKeyChecking=no "$TAR_FILE" "root@${worker}:${TAR_FILE}"
        ssh -o StrictHostKeyChecking=no "root@${worker}" "/usr/local/bin/k3s ctr --namespace k8s.io images import ${TAR_FILE} && rm -f ${TAR_FILE}"
    fi
done
rm -f "$TAR_FILE"

# 3. Apply Kubernetes Manifests
echo "🚢 Step 3: Applying Kubernetes manifests..."
kubectl apply -f "$MANIFEST_PATH"

# 4. Rollout Restart to pull the new imported image
echo "🔄 Step 4: Triggering K8s rolling update..."
kubectl rollout restart "deployment/${NAME}"

echo "✅ [$NAME] deployed successfully!"
