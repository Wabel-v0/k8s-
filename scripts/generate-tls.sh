#!/bin/bash
# DEPRECATED: This script is no longer needed!
# TLS certificates are now automatically managed by cert-manager.
#
# See cert-manager/ folder for:
# - issuer.yaml: ClusterIssuer configuration
# - certificate.yaml: Certificate resource
#
# The certificate is automatically created when you run:
#   make deploy-cert-manager
#   make deploy-gateway
#
# To check certificate status:
#   kubectl get certificate -n backend
#   kubectl get secret app-tls -n backend

echo "⚠️  DEPRECATED: This script is no longer used."
echo ""
echo "TLS certificates are now automatically managed by cert-manager."
echo ""
echo "To set up certificates, run:"
echo "  make deploy-cert-manager"
echo "  make deploy-gateway"
echo ""
echo "To check certificate status:"
echo "  kubectl get certificate -n backend"
echo "  kubectl describe certificate app-cert -n backend"
echo "  kubectl get secret app-tls -n backend"
exit 1
