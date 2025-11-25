#!/bin/bash
set -e

echo "🔌 Connecting Kubernetes services to external Docker containers..."

# Get the host IP that the Kind container can reach
# On macOS/Linux, Docker containers can reach host via host.docker.internal
# But Kind needs the actual IP of the docker0 or host network interface

# For macOS with Docker Desktop
if [[ "$OSTYPE" == "darwin"* ]]; then
  # On macOS, Docker Desktop provides host.docker.internal
  # Get the Kind container's gateway (which routes to host)
  HOST_IP=$(docker exec k8s-project-control-plane getent hosts host.docker.internal | awk '{ print $1 }')
  
  if [ -z "$HOST_IP" ]; then
    echo "⚠️  Could not resolve host.docker.internal, using docker network gateway..."
    HOST_IP=$(docker network inspect kind | jq -r '.[0].IPAM.Config[0].Gateway')
  fi
else
  # On Linux, get the docker0 bridge IP or kind network gateway
  HOST_IP=$(docker network inspect kind | jq -r '.[0].IPAM.Config[0].Gateway')
  
  if [ -z "$HOST_IP" ]; then
    HOST_IP=$(ip -4 addr show docker0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  fi
fi

if [ -z "$HOST_IP" ]; then
  echo "❌ Could not determine host IP"
  echo "Please manually get your host IP that Kind can reach and update the endpoints"
  exit 1
fi

echo "✓ Host IP detected: $HOST_IP"
echo "  (This is the IP that Kind containers will use to reach host services)"

# Create backend namespace
kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f -

# Deploy PostgreSQL endpoint
echo "Deploying external PostgreSQL endpoint..."
sed "s/HOST_IP_PLACEHOLDER/$HOST_IP/" k8s/external-postgres-service.yaml | kubectl apply -f -

# Deploy Mock S3 endpoint
echo "Deploying external Mock S3 endpoint..."
sed "s/HOST_IP_PLACEHOLDER/$HOST_IP/" k8s/external-mock-s3-service.yaml | kubectl apply -f -

echo ""
echo "✅ External service endpoints created:"
echo "   - external-postgres:5432 → $HOST_IP:5433"
echo "   - external-mock-s3:9090 → $HOST_IP:9090"
echo ""
echo "Your services can now access:"
echo "   - Auth service → external-postgres.backend.svc.cluster.local:5432"
echo "   - Storage service → external-mock-s3.backend.svc.cluster.local:9090"



