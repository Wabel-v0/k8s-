#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Testing All Service Endpoints${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

FAILED=0
PASSED=0

test_endpoint() {
    local name="$1"
    local url="$2"
    local expected="$3"
    
    echo -n "Testing $name... "
    RESPONSE=$(curl -sk "$url" 2>&1)
    
    if echo "$RESPONSE" | grep -q "$expected"; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo -e "${RED}  Expected: $expected${NC}"
        echo -e "${RED}  Got: ${RESPONSE:0:100}${NC}"
        FAILED=$((FAILED + 1))
    fi
}

# Main API Tests
echo -e "${YELLOW}Main API Tests:${NC}"
test_endpoint "Main API Root" "https://main-api.internal:8443/" "Main API"
test_endpoint "Main API Health" "https://main-api.internal:8443/healthz" "ok"
test_endpoint "Main API Metrics" "https://main-api.internal:8443/metrics" "main_api_requests_total"

echo ""
echo -e "${YELLOW}Downstream Service Tests (via Main API):${NC}"
test_endpoint "Auth Service" "https://main-api.internal:8443/auth" "Auth Service"
test_endpoint "Storage Service" "https://main-api.internal:8443/storage" "Storage Service"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
echo -e "  ${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Check the output above.${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "  1. Check if services are running: kubectl get pods -n api && kubectl get pods -n backend"
    echo "  2. Check gateway: kubectl get gateway -n api"
    echo "  3. Check external services: docker ps | grep external"
    echo "  4. Check port-forwards: pgrep -f port-forward"
    exit 1
fi


