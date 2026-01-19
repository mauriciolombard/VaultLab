#!/bin/bash
# cleanup.sh
# Removes all Kubernetes auth configuration from Vault and Kubernetes resources
# The Vault cluster itself remains intact

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "  Kubernetes Auth Cleanup"
echo "============================================"
echo ""
echo -e "${YELLOW}WARNING: This will remove:${NC}"
echo "  - Vault Kubernetes auth method and roles"
echo "  - Kubernetes test resources (vault-test namespace)"
echo "  - Vault Agent Injector (vault namespace)"
echo "  - vault-auth ServiceAccount"
echo ""
echo "The Vault cluster will remain intact."
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo "-------------------"

# Clean up Vault configuration
if [ -n "$VAULT_ADDR" ] && [ -n "$VAULT_TOKEN" ]; then
    echo ""
    echo "Cleaning up Vault configuration..."

    # Disable kubernetes auth
    if vault auth list 2>/dev/null | grep -q "^kubernetes/"; then
        echo "  Disabling kubernetes auth method..."
        vault auth disable kubernetes || echo "  Could not disable kubernetes auth"
    fi

    # Remove the policy
    echo "  Removing k8s-test-policy..."
    vault policy delete k8s-test-policy 2>/dev/null || echo "  Policy may not exist"

    echo -e "${GREEN}✓${NC} Vault cleanup complete"
else
    echo -e "${YELLOW}!${NC} VAULT_ADDR or VAULT_TOKEN not set, skipping Vault cleanup"
    echo "  To clean up Vault manually:"
    echo "  $ vault auth disable kubernetes"
    echo "  $ vault policy delete k8s-test-policy"
fi

# Clean up Kubernetes resources
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null 2>&1; then
    echo ""
    echo "Cleaning up Kubernetes resources..."

    # Delete test namespace (this deletes all resources in it)
    echo "  Deleting vault-test namespace..."
    kubectl delete namespace vault-test --ignore-not-found=true

    # Delete vault namespace (injector)
    echo "  Deleting vault namespace..."
    kubectl delete namespace vault --ignore-not-found=true

    # Delete vault-auth service account and related resources
    echo "  Deleting vault-auth resources..."
    kubectl delete secret vault-auth-token -n kube-system --ignore-not-found=true
    kubectl delete serviceaccount vault-auth -n kube-system --ignore-not-found=true
    kubectl delete clusterrolebinding vault-auth-delegator --ignore-not-found=true

    # Delete any test ClusterRoleBindings
    kubectl delete clusterrolebinding vault-test-auth-delegator --ignore-not-found=true

    echo -e "${GREEN}✓${NC} Kubernetes cleanup complete"
else
    echo -e "${YELLOW}!${NC} kubectl not available or cluster not running, skipping Kubernetes cleanup"
fi

# Stop ngrok if running
echo ""
echo "Checking for ngrok process..."
if pgrep -x "ngrok" > /dev/null; then
    echo "  Stopping ngrok..."
    pkill -x ngrok || true
    echo -e "${GREEN}✓${NC} ngrok stopped"
else
    echo "  ngrok is not running"
fi

# Clean up temp files
echo ""
echo "Cleaning up temp files..."
rm -f /tmp/ngrok-k8s-url.txt
rm -f /tmp/ngrok-k8s-config.yml
rm -f /tmp/ngrok.log
rm -f /tmp/vault-agent-values.yaml
echo -e "${GREEN}✓${NC} Temp files cleaned"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Cleanup Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "To also stop Minikube:"
echo "  $ minikube stop"
echo "  $ minikube delete  (to fully remove)"
echo ""
echo "The Vault cluster remains intact and accessible."
