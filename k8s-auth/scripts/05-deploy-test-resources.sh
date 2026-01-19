#!/bin/bash
# 05-deploy-test-resources.sh
# Deploys test resources to Kubernetes for testing Vault authentication
# Creates namespace, service account, and test pods

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$SCRIPT_DIR/../k8s-manifests"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "============================================"
echo "  Deploy Test Resources"
echo "============================================"
echo ""

# Check required environment variables
echo "Checking environment variables..."
if [ -z "$VAULT_ADDR" ]; then
    echo -e "${RED}ERROR: VAULT_ADDR is not set${NC}"
    echo "Export it with: export VAULT_ADDR=\"http://<your-nlb-dns>:8200\""
    exit 1
fi
echo -e "${GREEN}✓${NC} VAULT_ADDR: $VAULT_ADDR"
echo ""

# Check if Minikube is running
if ! minikube status &> /dev/null; then
    echo -e "${RED}ERROR: Minikube is not running${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Minikube is running"
echo ""

# Apply all manifests
echo "Applying Kubernetes manifests..."
echo "---------------------------------"
echo ""

# Create namespace
echo "Creating vault-test namespace..."
kubectl apply -f "$MANIFEST_DIR/namespace.yaml"
echo ""

# Create service accounts
echo "Creating ServiceAccounts..."
kubectl apply -f "$MANIFEST_DIR/serviceaccount.yaml"
echo ""

# Create cluster role binding
echo "Creating ClusterRoleBinding..."
kubectl apply -f "$MANIFEST_DIR/clusterrolebinding.yaml"
echo ""

# Wait a moment for service accounts to be ready
sleep 2

# Create test pod (manual auth)
echo "Creating test-pod-manual..."
# Substitute VAULT_ADDR in the manifest
sed "s|\${VAULT_ADDR}|$VAULT_ADDR|g" "$MANIFEST_DIR/test-pod-manual.yaml" | kubectl apply -f -
echo ""

# Create test pod (injector)
echo "Creating test-pod-injector..."
sed "s|\${VAULT_ADDR}|$VAULT_ADDR|g" "$MANIFEST_DIR/test-pod-injector.yaml" | kubectl apply -f -
echo ""

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
echo "-------------------------------"
kubectl wait --for=condition=Ready pod/test-pod-manual -n vault-test --timeout=120s || echo "test-pod-manual may still be starting..."

# The injector pod takes longer due to init container
echo "Waiting for test-pod-injector (this may take a minute due to init container)..."
kubectl wait --for=condition=Ready pod/test-pod-injector -n vault-test --timeout=180s || echo "test-pod-injector may still be initializing..."

echo ""
echo "Resources in vault-test namespace:"
echo "-----------------------------------"
kubectl get all -n vault-test
echo ""

echo "ServiceAccounts:"
kubectl get serviceaccounts -n vault-test
echo ""

echo "Pod details:"
kubectl describe pod -n vault-test | grep -A5 "^Name:\|^Status:"
echo ""

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Test Resources Deployed!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Two test pods are now running:"
echo ""
echo "1. test-pod-manual - For manual Vault CLI authentication"
echo "   Test with:"
echo "   $ kubectl exec -it test-pod-manual -n vault-test -- /bin/sh"
echo "   $ vault write auth/kubernetes/login role=test-role jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token"
echo ""
echo "2. test-pod-injector - For Vault Agent sidecar injection"
echo "   Check injected secrets:"
echo "   $ kubectl exec test-pod-injector -n vault-test -- cat /vault/secrets/config.txt"
echo ""
echo "Next step: Run ./scripts/test-k8s-auth.sh to validate everything"
