#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Monitoring Stack Health Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. Check if services are running
echo -e "${YELLOW}1. Checking service pods...${NC}"
API_PODS=$(kubectl get pods -n api -l app=main-api --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
AUTH_PODS=$(kubectl get pods -n backend -l app=auth-service --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
STORAGE_PODS=$(kubectl get pods -n backend -l app=storage-service --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

if [ $API_PODS -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} main-api: $API_PODS running"
else
    echo -e "  ${RED}✗${NC} main-api: No running pods"
fi

if [ $AUTH_PODS -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} auth-service: $AUTH_PODS running"
else
    echo -e "  ${RED}✗${NC} auth-service: No running pods"
fi

if [ $STORAGE_PODS -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} storage-service: $STORAGE_PODS running"
else
    echo -e "  ${RED}✗${NC} storage-service: No running pods"
fi

echo ""

# 2. Check if Prometheus is scraping
echo -e "${YELLOW}2. Checking Prometheus targets...${NC}"
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
    wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
    grep -o '"job":"[^"]*"' | grep -E '(main-api|auth-service|storage-service)' | \
    sort -u | sed 's/"job":"/  • /' | sed 's/"//'

echo ""

# 3. Check if metrics are being collected
echo -e "${YELLOW}3. Checking if metrics are available...${NC}"
for service in main-api auth-service storage-service; do
    RESULT=$(kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
        wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"$service\"}" 2>/dev/null | \
        grep -o '"result":\[[^]]*\]' 2>/dev/null)
    
    if echo "$RESULT" | grep -q '"value":\['; then
        echo -e "  ${GREEN}✓${NC} $service: Metrics available"
    else
        echo -e "  ${RED}✗${NC} $service: No metrics"
    fi
done

echo ""

# 4. Check PrometheusRule
echo -e "${YELLOW}4. Checking alert rules...${NC}"
RULES=$(kubectl get prometheusrules microservices-alerts -n monitoring -o jsonpath='{.spec.groups[*].rules[*].alert}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' | wc -l)
if [ $RULES -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} $RULES alert rules configured"
    kubectl get prometheusrules microservices-alerts -n monitoring -o jsonpath='{.spec.groups[*].rules[*].alert}' 2>/dev/null | tr ' ' '\n' | sed 's/^/    - /'
else
    echo -e "  ${RED}✗${NC} No alert rules found"
fi

echo ""

# 5. Check current alerts
echo -e "${YELLOW}5. Checking active alerts...${NC}"
ALERTS=$(kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
    wget -qO- 'http://localhost:9090/api/v1/alerts' 2>/dev/null | \
    grep -o '"alertname":"[^"]*"' | grep -v Watchdog | wc -l)

if [ $ALERTS -gt 0 ]; then
    echo -e "  ${YELLOW}⚠${NC}  $ALERTS active alerts"
    kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
        wget -qO- 'http://localhost:9090/api/v1/alerts' 2>/dev/null | \
        grep -o '"alertname":"[^"]*"' | sed 's/"alertname":"/    - /' | sed 's/"//' | sort -u
else
    echo -e "  ${GREEN}✓${NC} No active alerts (system healthy)"
fi

echo ""

# 6. Check ServiceMonitors
echo -e "${YELLOW}6. Checking ServiceMonitors...${NC}"
for service in main-api auth-service storage-service; do
    SM=$(kubectl get servicemonitor $service -n monitoring 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $service ServiceMonitor exists"
    else
        echo -e "  ${RED}✗${NC} $service ServiceMonitor missing"
    fi
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}========================================${NC}"

TOTAL_ISSUES=0

if [ $API_PODS -eq 0 ] || [ $AUTH_PODS -eq 0 ] || [ $STORAGE_PODS -eq 0 ]; then
    echo -e "${RED}✗ Some services are not running${NC}"
    echo -e "  Fix: kubectl get pods -n api && kubectl get pods -n backend"
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi

if [ $RULES -eq 0 ]; then
    echo -e "${RED}✗ Alert rules not configured${NC}"
    echo -e "  Fix: kubectl apply -f k8s/monitoring/prometheus-alerts.yaml"
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi

if [ $TOTAL_ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ Monitoring stack is healthy!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "  1. Run chaos: ${YELLOW}make chaos-menu${NC}"
    echo -e "  2. Watch alerts: ${YELLOW}make alertmanager-ui${NC}"
    echo -e "  3. Check Grafana: ${YELLOW}make grafana-ui${NC}"
else
    echo -e "${RED}Found $TOTAL_ISSUES issues. Please fix them before running chaos scenarios.${NC}"
fi

echo ""


