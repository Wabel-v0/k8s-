#!/bin/bash
set -e

echo "🔍 Verifying TLS Certificate Setup"
echo ""

# Check cert-manager is running
echo "1️⃣  Checking cert-manager pods..."
if kubectl get pods -n cert-manager &> /dev/null; then
    kubectl get pods -n cert-manager
    echo "✅ cert-manager is running"
else
    echo "❌ cert-manager namespace not found"
    echo "Run: make deploy-cert-manager"
    exit 1
fi
echo ""

# Check ClusterIssuer
echo "2️⃣  Checking ClusterIssuer..."
if kubectl get clusterissuer selfsigned-issuer &> /dev/null; then
    ISSUER_STATUS=$(kubectl get clusterissuer selfsigned-issuer -o jsonpath='{.status.conditions[0].status}')
    if [ "$ISSUER_STATUS" = "True" ]; then
        echo "✅ ClusterIssuer 'selfsigned-issuer' is ready"
    else
        echo "⚠️  ClusterIssuer exists but not ready"
        kubectl get clusterissuer selfsigned-issuer
    fi
else
    echo "❌ ClusterIssuer 'selfsigned-issuer' not found"
    echo "Run: kubectl apply -f cert-manager/issuer.yaml"
    exit 1
fi
echo ""

# Check Certificate
echo "3️⃣  Checking Certificate..."
if kubectl get certificate app-cert -n backend &> /dev/null; then
    CERT_STATUS=$(kubectl get certificate app-cert -n backend -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$CERT_STATUS" = "True" ]; then
        echo "✅ Certificate 'app-cert' is ready"
    else
        echo "⚠️  Certificate exists but not ready yet"
        echo "This is normal if just deployed. Wait a few seconds..."
        kubectl get certificate app-cert -n backend
    fi
else
    echo "❌ Certificate 'app-cert' not found in backend namespace"
    echo "Run: kubectl apply -f cert-manager/certificate.yaml"
    exit 1
fi
echo ""

# Check Secret
echo "4️⃣  Checking TLS Secret..."
if kubectl get secret app-tls -n backend &> /dev/null; then
    echo "✅ TLS Secret 'app-tls' exists"
    
    # Show certificate details
    CERT_DATA=$(kubectl get secret app-tls -n backend -o jsonpath='{.data.tls\.crt}' | base64 -d)
    EXPIRY=$(echo "$CERT_DATA" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    SUBJECT=$(echo "$CERT_DATA" | openssl x509 -noout -subject 2>/dev/null | cut -d= -f2-)
    
    echo "   Subject: $SUBJECT"
    echo "   Expires: $EXPIRY"
else
    echo "❌ TLS Secret 'app-tls' not found"
    echo "Wait for cert-manager to create it, or check certificate status:"
    echo "  kubectl describe certificate app-cert -n backend"
    exit 1
fi
echo ""

# Check Ingress
echo "5️⃣  Checking Ingress configuration..."
if kubectl get ingress gateway -n backend &> /dev/null; then
    echo "✅ Ingress 'gateway' exists"
    
    # Check if TLS is configured
    TLS_HOSTS=$(kubectl get ingress gateway -n backend -o jsonpath='{.spec.tls[0].hosts[0]}')
    TLS_SECRET=$(kubectl get ingress gateway -n backend -o jsonpath='{.spec.tls[0].secretName}')
    
    if [ ! -z "$TLS_HOSTS" ]; then
        echo "   TLS Host: $TLS_HOSTS"
        echo "   TLS Secret: $TLS_SECRET"
        
        if [ "$TLS_SECRET" = "app-tls" ]; then
            echo "✅ Ingress is correctly configured to use app-tls"
        else
            echo "⚠️  Ingress is using a different secret: $TLS_SECRET"
        fi
    else
        echo "⚠️  Ingress does not have TLS configured"
    fi
else
    echo "❌ Ingress 'gateway' not found"
    echo "Run: make deploy-gateway"
    exit 1
fi
echo ""

# Final verification
echo "═══════════════════════════════════════════════════════════"
echo "✅ TLS SETUP VERIFIED!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "You can now access your application via HTTPS:"
echo "  https://app.local"
echo ""
echo "Note: You'll see a certificate warning (self-signed cert)"
echo "      Click 'Advanced' → 'Proceed to app.local'"
echo ""
echo "To test the endpoints:"
echo "  make test-endpoints"
echo ""



