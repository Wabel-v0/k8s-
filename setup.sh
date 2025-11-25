#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   K8s Microservices - Automated Setup${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

MISSING_DEPS=0

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo "  Install: https://www.docker.com/products/docker-desktop"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓ Docker${NC}"
fi

if ! command -v minikube &> /dev/null; then
    echo -e "${RED}✗ Minikube not found${NC}"
    echo "  Install: brew install minikube (macOS) or see SETUP_GUIDE.md"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓ Minikube${NC}"
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    echo "  Install: brew install kubectl (macOS) or see SETUP_GUIDE.md"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓ kubectl${NC}"
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}✗ Helm not found${NC}"
    echo "  Install: brew install helm (macOS) or see SETUP_GUIDE.md"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓ Helm${NC}"
fi

if ! command -v mkcert &> /dev/null; then
    echo -e "${RED}✗ mkcert not found${NC}"
    echo "  Install: brew install mkcert (macOS) or see SETUP_GUIDE.md"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓ mkcert${NC}"
fi

if [ $MISSING_DEPS -eq 1 ]; then
    echo ""
    echo -e "${RED}Missing dependencies. Please install them first.${NC}"
    echo -e "See ${YELLOW}SETUP_GUIDE.md${NC} for installation instructions."
    exit 1
fi

echo ""
echo -e "${GREEN}All prerequisites found!${NC}"
echo ""

# Confirm before proceeding
echo -e "${YELLOW}This script will:${NC}"
echo "  1. Start Minikube cluster"
echo "  2. Create namespaces"
echo "  3. Install monitoring stack (Prometheus, Grafana)"
echo "  4. Setup HTTPS certificates"
echo "  5. Install Gateway API"
echo "  6. Deploy microservices"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo ""

# Step 1: Start Minikube
echo -e "${BLUE}[1/7]${NC} Starting Minikube..."
minikube start --cpus=4 --memory=8192 --disk-size=20g --driver=docker
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to start Minikube. Check Docker is running.${NC}"
    exit 1
fi

# Enable addons
minikube addons enable ingress
minikube addons enable metrics-server

echo -e "${GREEN}✓ Minikube started${NC}"
echo ""

# Step 2: Create namespaces
echo -e "${BLUE}[2/7]${NC} Creating namespaces..."
kubectl create namespace api --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespaces created${NC}"
echo ""

# Step 3: Install monitoring stack
echo -e "${BLUE}[3/7]${NC} Installing monitoring stack (takes 2-3 minutes)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts > /dev/null 2>&1
helm repo update > /dev/null 2>&1

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --wait --timeout=5m

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to install monitoring stack.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Monitoring stack installed${NC}"
echo ""

# Step 4: Setup certificates
echo -e "${BLUE}[4/7]${NC} Setting up HTTPS certificates..."

# Install mkcert CA
mkcert -install > /dev/null 2>&1

# Create certs directory if not exists
mkdir -p certs

# Generate certificate
cd certs
mkcert main-api.internal > /dev/null 2>&1
cd ..

# Add to /etc/hosts if not already there
if ! grep -q "main-api.internal" /etc/hosts; then
    echo "127.0.0.1 main-api.internal" | sudo tee -a /etc/hosts > /dev/null
fi

# Create TLS secret
kubectl create secret tls mkcert \
  --cert=certs/main-api.internal.pem \
  --key=certs/main-api.internal-key.pem \
  -n api --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ HTTPS certificates configured${NC}"
echo ""

# Step 5: Install Gateway API
echo -e "${BLUE}[5/7]${NC} Installing Envoy Gateway..."
kubectl apply --server-side --force-conflicts -f https://github.com/envoyproxy/gateway/releases/download/v1.5.1/install.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to install Envoy Gateway.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Envoy Gateway installed${NC}"
echo ""

# Step 6: Deploy services
echo -e "${BLUE}[6/6]${NC} Deploying microservices..."
kubectl apply -f k8s/gateway/ -R > /dev/null 2>&1
kubectl apply -f k8s/main-api/ -R > /dev/null 2>&1
kubectl apply -f k8s/auth-service/ -R > /dev/null 2>&1
kubectl apply -f k8s/storage/ -R > /dev/null 2>&1
kubectl apply -f k8s/monitoring/ -R > /dev/null 2>&1

echo "  Waiting for deployments to be ready..."
kubectl wait --for=condition=available deployment/main-api -n api --timeout=300s > /dev/null 2>&1
kubectl wait --for=condition=available deployment/auth-service -n backend --timeout=300s > /dev/null 2>&1
kubectl wait --for=condition=available deployment/storage-service -n backend --timeout=300s > /dev/null 2>&1

echo -e "${GREEN}✓ Microservices deployed${NC}"
echo ""

# Setup complete
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}          Setup Complete! 🎉${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Start port-forwards:"
echo -e "   ${GREEN}make start-all${NC}"
echo ""
echo "2. Open Grafana at http://localhost:3000"
echo "   (credentials shown in start-all output)"
echo ""
echo "3. Try chaos engineering:"
echo -e "   ${GREEN}make chaos-menu${NC}"
echo ""
echo -e "${YELLOW}📚 Documentation:${NC}"
echo "   - README.md        - Main documentation"
echo "   - SETUP_GUIDE.md   - Setup guide"
echo "   - RESULTS.md       - Testing & chaos scenarios"
echo ""
echo -e "${GREEN}Happy learning! 🚀${NC}"

