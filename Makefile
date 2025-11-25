.PHONY: help deploy apply start-all stop-all status chaos-menu chaos-pod-kill chaos-cpu-stress chaos-memory-stress chaos-random chaos-all-recovery
.PHONY: load-auth load-storage

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m
RED    := \033[0;31m
NC     := \033[0m # No Color

# Load environment from .env if present (for SLACK_WEBHOOK_URL, SLACK_CHANNEL, etc.)
-include .env
export SLACK_WEBHOOK_URL SLACK_CHANNEL

help: ## Show available commands
	@echo "$(BLUE)════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)   Try me$(NC)"
	@echo "$(BLUE)════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(GREEN)Available Commands:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | sed 's/:.*## /##/' | awk -F'##' '{printf "  \033[0;33m%-25s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Quick Start:$(NC)"
	@echo "  1. First time: $(YELLOW)make deploy$(NC) (installs everything)"
	@echo "  2. Daily use:  $(YELLOW)make start-all$(NC)"
	@echo "  3. View dashboards: Open http://localhost:3000"
	@echo "  4. Run chaos: $(YELLOW)make chaos-menu$(NC)"
	@echo "  5. Stop: $(YELLOW)make stop-all$(NC)"
	@echo ""

alerts-apply: ## Apply Prometheus rules and Alertmanager config (uses env vars)
	@echo "$(GREEN)Applying alert rules and Alertmanager config...$(NC)"
	@[ -n "$$SLACK_WEBHOOK_URL" ] || (echo "$(RED)SLACK_WEBHOOK_URL is required$(NC)" && exit 1)
	@echo "$(YELLOW)1/2 Updating Prometheus alert rules$(NC)"
	@kubectl apply -n monitoring -f k8s/monitoring/prometheus/prometheus-alerts.yaml
	@echo "$(YELLOW)2/2 Updating Alertmanager secret via envsubst$(NC)"
	@SLACK_WEBHOOK_URL="$$SLACK_WEBHOOK_URL" SLACK_CHANNEL="$${SLACK_CHANNEL:-#alerts}" envsubst < k8s/monitoring/prometheus/alertmanager-config.yaml | kubectl apply -f -
	@echo "$(GREEN)✓ Alerts applied$(NC)"
	@echo ""
	@echo "$(BLUE)Tip:$(NC) To set values just for this run:"
	@echo "  SLACK_WEBHOOK_URL=... SLACK_CHANNEL=#ops make alerts-apply"

deploy: ## Install monitoring, Metrics Server, Gateway API, services
	@echo "$(GREEN)════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)    Installing Everything$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)[1/7]$(NC) Creating namespaces..."
	@kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
	@kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
	@echo "$(GREEN)✓ Namespaces created$(NC)"
	@echo ""
	@echo "$(YELLOW)[2/7]$(NC) Enabling Minikube Metrics Server addon..."
	@if command -v minikube > /dev/null 2>&1; then \
		minikube addons enable metrics-server > /dev/null 2>&1 || true; \
		echo "$(GREEN)✓ metrics-server addon enabled (or already enabled)$(NC)"; \
	else \
		echo "$(RED)Minikube not detected. Please install Minikube and run 'minikube addons enable metrics-server'.$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)[3/7]$(NC) Setting up HTTPS certificates with mkcert..."
	@if ! command -v mkcert > /dev/null 2>&1; then \
		echo "$(RED)✗ mkcert not found. Please install it first.$(NC)"; \
		echo "  macOS: brew install mkcert"; \
		echo "  Linux: See https://github.com/FiloSottile/mkcert"; \
		exit 1; \
	fi
	@mkcert -install > /dev/null 2>&1
	@mkdir -p certs
	@cd certs && mkcert main-api.internal > /dev/null 2>&1 || true
	@if ! grep -q "main-api.internal" /etc/hosts 2>/dev/null; then \
		echo "127.0.0.1 main-api.internal" | sudo tee -a /etc/hosts > /dev/null; \
	fi
	@kubectl create secret tls mkcert \
	  --cert=certs/main-api.internal.pem \
	  --key=certs/main-api.internal-key.pem \
	  -n backend --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
	@echo "$(GREEN)✓ HTTPS certificates configured$(NC)"
	@echo ""
	@echo "$(YELLOW)[4/7]$(NC) Installing kube-prometheus-stack (this may take 2-3 minutes)..."
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts > /dev/null 2>&1 || true
	@helm repo update > /dev/null 2>&1
	@helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
	  --namespace monitoring \
	  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
	  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
	  --set prometheus.prometheusSpec.scrapeInterval=5s \
	  --set prometheus.prometheusSpec.evaluationInterval=5s \
	  --set grafana.enabled=true \
	  --set grafana.adminPassword=admin \
	  --set grafana.resources.requests.cpu=100m \
	  --set grafana.resources.requests.memory=256Mi \
	  --set grafana.resources.limits.cpu=300m \
	  --set grafana.resources.limits.memory=512Mi \
	  --set alertmanager.alertmanagerSpec.resources.requests.cpu=50m \
	  --set alertmanager.alertmanagerSpec.resources.requests.memory=128Mi \
	  --set alertmanager.alertmanagerSpec.resources.limits.cpu=200m \
	  --set alertmanager.alertmanagerSpec.resources.limits.memory=256Mi \
	  --set prometheus.prometheusSpec.resources.requests.cpu=200m \
	  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
	  --set prometheus.prometheusSpec.resources.limits.cpu=500m \
	  --set prometheus.prometheusSpec.resources.limits.memory=1Gi \
	  --set grafana.sidecar.dashboards.enabled=true \
	  --set grafana.sidecar.dashboards.label=grafana_dashboard \
	  --wait --timeout=5m > /dev/null 2>&1
	@echo "$(GREEN)✓ Monitoring stack installed$(NC)"
	@echo ""
	@echo "$(YELLOW)[5/7]$(NC) Installing Envoy Gateway..."
	@kubectl apply --server-side --force-conflicts -f https://github.com/envoyproxy/gateway/releases/download/v1.5.1/install.yaml
	@echo "$(GREEN)✓ Envoy Gateway installed$(NC)"
	@echo ""
	@echo "$(YELLOW)[6/7]$(NC) Waiting for Envoy Gateway to be ready..."
	@kubectl wait --for=condition=available deployment/envoy-gateway -n envoy-gateway-system --timeout=3m > /dev/null 2>&1 || true
	@echo "$(GREEN)✓ Envoy Gateway ready$(NC)"
	@echo ""
	@echo "$(YELLOW)[7/7]$(NC) Deploying microservices..."
	@$(MAKE) apply
	@echo "$(GREEN)✓ All services deployed$(NC)"
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)         Deployment Complete! 🎉$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(BLUE)Next Steps:$(NC)"
	@echo "  1. Run: $(YELLOW)make start-all$(NC)"
	@echo "  2. Open Grafana: $(YELLOW)http://localhost:3000$(NC)"
	@echo "  3. Try chaos: $(YELLOW)make chaos-menu$(NC)"
	@echo ""

apply: ## Apply/update all Kubernetes manifests (services only, not monitoring)
	@echo "$(YELLOW)Applying Kubernetes manifests...$(NC)"
	@echo ""
	@echo "  • Applying gateway configuration..."
	@kubectl apply -f k8s/gateway/ -R
	@echo "  • Applying main-api..."
	@kubectl apply -f k8s/main-api/ -R
	@echo "  • Applying auth-service..."
	@kubectl apply -f k8s/auth-service/ -R
	@echo "  • Applying storage-service..."
	@kubectl apply -f k8s/storage/ -R
	@echo "  • Applying monitoring dashboards..."
	@kubectl apply -f k8s/monitoring/ -R
	@echo ""
	@echo "$(YELLOW)Waiting for deployments to be ready...$(NC)"
	@kubectl wait --for=condition=available deployment/main-api -n backend --timeout=120s 2>/dev/null || echo "$(YELLOW)  main-api: still starting...$(NC)"
	@kubectl wait --for=condition=available deployment/auth-service -n backend --timeout=120s 2>/dev/null || echo "$(YELLOW)  auth-service: still starting...$(NC)"
	@kubectl wait --for=condition=available deployment/storage-service -n backend --timeout=120s 2>/dev/null || echo "$(YELLOW)  storage-service: still starting...$(NC)"
	@echo ""
	@echo "$(GREEN)✓ Manifests applied$(NC)"

start-all: ## Start all port-forwards (Grafana, Prometheus, Gateway)
	@echo "$(GREEN)Starting all services...$(NC)"
	@echo ""
	@echo "$(YELLOW)1. Starting Prometheus port-forward...$(NC)"
	@if pgrep -f "port-forward.*prometheus.*9090" > /dev/null; then \
		echo "$(YELLOW)   Already running$(NC)"; \
	else \
		kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 > /dev/null 2>&1 & \
		echo "$(GREEN)   ✓ Started on port 9090$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)2. Starting Grafana port-forward...$(NC)"
	@if pgrep -f "port-forward.*grafana.*3000" > /dev/null; then \
		echo "$(YELLOW)   Already running$(NC)"; \
	else \
		kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 > /dev/null 2>&1 & \
		echo "$(GREEN)   ✓ Started on port 3000$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)3. Starting API Gateway port-forward...$(NC)"
	@GATEWAY_SVC=$$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=api-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$GATEWAY_SVC" ]; then \
		echo "$(RED)   Gateway service not found. Run 'make deploy' first.$(NC)"; \
	else \
		if pgrep -f "port-forward.*envoy.*8443" > /dev/null; then \
			echo "$(YELLOW)   Already running$(NC)"; \
		else \
			kubectl port-forward -n envoy-gateway-system svc/$$GATEWAY_SVC 8443:443 > /dev/null 2>&1 & \
			echo "$(GREEN)   ✓ Started on port 8443$(NC)"; \
		fi; \
	fi
	@sleep 2
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)         All services started successfully!$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(BLUE)Access URLs:$(NC)"
	@echo "  • Grafana:    $(YELLOW)http://localhost:3000$(NC)"
	@echo "  • Prometheus: $(YELLOW)http://localhost:9090$(NC)"
	@echo "  • API:        $(YELLOW)https://main-api.internal:8443$(NC)"
	@echo ""
	@echo "$(BLUE)Grafana Credentials:$(NC)"
	@echo "  Username: $(GREEN)admin$(NC)"
	@echo "  Password: $(GREEN)admin$(NC)"
	@echo ""
	@echo "$(BLUE)Test the API:$(NC)"
	@echo "  curl -k https://main-api.internal:8443/"
	@echo ""

stop-all: ## Stop all port-forwards
	@echo "$(YELLOW)Stopping all port-forwards...$(NC)"
	@pkill -f "port-forward.*prometheus.*9090" 2>/dev/null || true
	@pkill -f "port-forward.*grafana.*3000" 2>/dev/null || true
	@pkill -f "port-forward.*envoy.*8443" 2>/dev/null || true
	@echo "$(GREEN)✓ All port-forwards stopped$(NC)"

status: ## Check status of all pods and services
	@echo "$(BLUE)════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)   System Status$(NC)"
	@echo "$(BLUE)════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Backend Services:$(NC)"
	@kubectl get pods -n backend 2>/dev/null || echo "$(RED)No pods found in backend namespace$(NC)"
	@echo ""
	@echo "$(YELLOW)Monitoring Stack:$(NC)"
	@kubectl get pods -n monitoring -l "app.kubernetes.io/name in (prometheus,grafana)" 2>/dev/null || echo "$(RED)No monitoring pods found$(NC)"
	@echo ""
	@echo "$(YELLOW)Gateway:$(NC)"
	@kubectl get gateway -n backend 2>/dev/null || echo "$(RED)No gateway found$(NC)"

# Load testing
load-auth: ## Load test /auth endpoint (drives HPA)
	@echo "$(YELLOW)Starting load against /auth ...$(NC)"
	@echo "Use overrides: make load-auth DURATION=120 CONCURRENCY=50 SUCCESS_RATE=0.7"
	@echo "Watching HPA:  kubectl get hpa -n backend -w"
	@DURATION=$(DURATION) CONCURRENCY=$(CONCURRENCY) TIMEOUT=$(TIMEOUT) SLEEP=$(SLEEP) HEADERS=$(HEADERS) bash scripts/load-auth.sh

load-storage: ## Load test /storage endpoint (drives HPA)
	@echo "$(YELLOW)Starting load against /storage ...$(NC)"
	@echo "Use overrides: make load-storage DURATION=120 CONCURRENCY=50 SUCCESS_RATE=0.7"
	@echo "Watching HPA:  kubectl get hpa -n backend -w"
	@DURATION=$(DURATION) CONCURRENCY=$(CONCURRENCY) TIMEOUT=$(TIMEOUT) SLEEP=$(SLEEP) HEADERS=$(HEADERS) bash scripts/load-storage.sh

# Chaos Engineering Scenarios
chaos-menu: ## Show all chaos engineering scenarios
	@echo "$(RED)════════════════════════════════════════════════════$(NC)"
	@echo "$(RED)         Chaos Engineering Scenarios$(NC)"
	@echo "$(RED)════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Available Scenarios:$(NC)"
	@echo "  $(RED)make chaos-pod-kill$(NC)          - Kill random pod"
	@echo "  $(RED)make chaos-cpu-stress$(NC)        - CPU overload"
	@echo "  $(RED)make chaos-memory-stress$(NC)     - Memory stress"
	@echo "  $(RED)make chaos-random$(NC)            - Random scenario"
	@echo ""
	@echo "$(YELLOW)Recovery:$(NC)"
	@echo "  $(GREEN)make chaos-all-recovery$(NC)     - Recover from all failures"
	@echo ""
	@echo "$(BLUE)💡 Monitor failures in real-time:$(NC)"
	@echo "  • Grafana:      http://localhost:3000"
	@echo "  • Prometheus:   http://localhost:9090/alerts"
	@echo ""

chaos-pod-kill: ## Kill a random pod to test restart and recovery
	@echo "$(RED)🔥 CHAOS: Killing a random pod...$(NC)"
	@PODS=($$(kubectl get pods -n backend -l app=storage-service -o name 2>/dev/null)); \
	if [ $${#PODS[@]} -gt 0 ]; then \
		POD=$${PODS[$$RANDOM % $${#PODS[@]}]}; \
		echo "$(YELLOW)Deleting: $$POD$(NC)"; \
		kubectl delete $$POD -n backend; \
		echo "$(GREEN)✓ Pod deleted. Watch recovery with: kubectl get pods -n backend -w$(NC)"; \
	else \
		echo "$(RED)No pods found$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)Expected behavior:$(NC)"
	@echo "  • Pod should restart automatically"
	@echo "  • Readiness probe will delay traffic until ready"

chaos-cpu-stress: ## Stress test CPU to trigger high CPU alerts
	@echo "$(RED)🔥 CHAOS: Creating CPU stress on ALL main-api pods...$(NC)"
	@PODS=$$(kubectl get pods -n backend -l app=main-api -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); \
	if [ -n "$$PODS" ]; then \
		echo "$(YELLOW)Stressing CPU on pods: $$PODS$(NC)"; \
		for POD in $$PODS; do \
			kubectl exec -n backend $$POD -- sh -c "timeout 90 dd if=/dev/zero of=/dev/null bs=1M &" 2>/dev/null & \
		done; \
		wait; \
		echo "$(GREEN)✓ CPU stress running on all pods for 90 seconds$(NC)"; \
		echo "$(BLUE)Monitor:$(NC) kubectl top pod -n backend | kubectl get hpa -n backend -w"; \
	else \
		echo "$(RED)No pods found$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)Expected behavior:$(NC)"
	@echo "  • CPU usage will spike on ALL pods"
	@echo "  • HPA will scale up when average CPU > 20%"

chaos-memory-stress: ## Simulate memory stress to trigger OOM alerts
	@echo "$(RED)🔥 CHAOS: Creating memory stress on storage-service...$(NC)"
	@POD=$$(kubectl get pods -n backend -l app=storage-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$POD" ]; then \
		echo "$(YELLOW)Stressing memory on pod: $$POD$(NC)"; \
		kubectl exec -n backend $$POD -- python3 -c "import time; x=[]; [x.append(' '*1024*1024) for i in range(150)]; time.sleep(60)" 2>/dev/null & \
		echo "$(GREEN)✓ Memory stress running for 60 seconds (150MB allocation)$(NC)"; \
		echo "$(BLUE)Monitor:$(NC) kubectl top pod -n backend | grep storage"; \
	else \
		echo "$(RED)No pods found$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)Expected behavior:$(NC)"
	@echo "  • Memory usage will increase to ~150MB"
	@echo "  • Near limit of 256MB (alert at 85% = 217MB)"



chaos-random: ## Run random failure scenario
	@SCENARIOS=("chaos-pod-kill" "chaos-cpu-stress" "chaos-memory-stress"); \
	RANDOM_SCENARIO=$${SCENARIOS[$$RANDOM % $${#SCENARIOS[@]}]}; \
	echo "$(RED)🔥 CHAOS: Running random scenario: $$RANDOM_SCENARIO$(NC)"; \
	$(MAKE) $$RANDOM_SCENARIO

chaos-all-recovery: ## Recover from all chaos scenarios
	@echo "$(GREEN)Recovering all services...$(NC)"
	@echo ""
	@echo "$(YELLOW)Scaling deployments to normal...$(NC)"
	@kubectl scale deployment/main-api -n backend --replicas=1 2>/dev/null || true
	@kubectl scale deployment/auth-service -n backend --replicas=1 2>/dev/null || true
	@kubectl scale deployment/storage-service -n backend --replicas=1 2>/dev/null || true
	@echo "$(GREEN)✓ Deployments scaled$(NC)"
	@echo ""
	@echo "$(YELLOW)Waiting for pods to be ready...$(NC)"
	@sleep 10
	@kubectl wait --for=condition=ready pod -l app=main-api -n backend --timeout=60s 2>/dev/null || true
	@kubectl wait --for=condition=ready pod -l app=auth-service -n backend --timeout=60s 2>/dev/null || true
	@kubectl wait --for=condition=ready pod -l app=storage-service -n backend --timeout=60s 2>/dev/null || true
	@echo "$(GREEN)✓ Pods ready$(NC)"
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)         All services recovered!$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════$(NC)"
	@echo ""
	@kubectl get pods -n backend
