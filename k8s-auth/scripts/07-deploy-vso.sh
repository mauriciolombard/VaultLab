#!/bin/bash
# 07-deploy-vso.sh
# Deploys the Vault Secrets Operator (VSO) to Minikube using Helm
# VSO syncs Vault secrets to native Kubernetes Secrets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$SCRIPT_DIR/../k8s-manifests/vso"
MINIKUBE_PROFILE="vault-k8s"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "============================================"
echo "  Vault Secrets Operator Deployment"
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

if [ -z "$VAULT_TOKEN" ]; then
    echo -e "${RED}ERROR: VAULT_TOKEN is not set${NC}"
    echo "Export it with: export VAULT_TOKEN=\"<your-root-token>\""
    exit 1
fi
echo -e "${GREEN}✓${NC} VAULT_TOKEN is set"
echo ""

# Check if Minikube is running
echo "Checking Minikube..."
if ! minikube status -p $MINIKUBE_PROFILE &> /dev/null; then
    echo -e "${RED}ERROR: Minikube is not running${NC}"
    echo "Run ./scripts/01-setup-minikube.sh first"
    exit 1
fi
echo -e "${GREEN}✓${NC} Minikube is running"
echo ""

# Check if Helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${RED}ERROR: helm is not installed${NC}"
    echo "Install with: brew install helm"
    exit 1
fi
echo -e "${GREEN}✓${NC} Helm is installed"
echo ""

# Check if Kubernetes auth is enabled in Vault
echo "Checking Vault Kubernetes auth..."
if ! vault auth list 2>/dev/null | grep -q "^kubernetes/"; then
    echo -e "${RED}ERROR: Kubernetes auth is not enabled in Vault${NC}"
    echo "Run ./scripts/03-configure-vault-auth.sh first"
    exit 1
fi
echo -e "${GREEN}✓${NC} Kubernetes auth is enabled"
echo ""

# Add HashiCorp Helm repo
echo "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update
echo -e "${GREEN}✓${NC} Helm repo updated"
echo ""

# Create VSO role in Vault
echo "Creating VSO role in Vault..."
echo "-----------------------------"

# The VSO operator will use its own ServiceAccount to authenticate
vault write auth/kubernetes/role/vso-role \
    bound_service_account_names=vault-secrets-operator-controller-manager \
    bound_service_account_namespaces=vault-secrets-operator \
    policies=k8s-test-policy \
    ttl=1h \
    max_ttl=24h

echo -e "${GREEN}✓${NC} vso-role created in Vault"
echo ""

# Deploy VSO using Helm
echo "Deploying Vault Secrets Operator..."
echo "------------------------------------"

helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
    --namespace vault-secrets-operator \
    --create-namespace \
    --set "defaultVaultConnection.enabled=false" \
    --wait

echo ""
echo -e "${GREEN}✓${NC} Vault Secrets Operator deployed"
echo ""

# Wait for operator to be ready
echo "Waiting for VSO controller to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault-secrets-operator -n vault-secrets-operator --timeout=120s

echo ""
echo "VSO pod status:"
kubectl get pods -n vault-secrets-operator
echo ""

# Apply VSO CRD manifests
echo "Applying VSO Custom Resources..."
echo "---------------------------------"

# Check if manifest directory exists
if [ ! -d "$MANIFEST_DIR" ]; then
    echo -e "${RED}ERROR: VSO manifest directory not found at $MANIFEST_DIR${NC}"
    exit 1
fi

# Substitute VAULT_ADDR in manifests and apply
echo "Applying VaultConnection..."
sed "s|\${VAULT_ADDR}|$VAULT_ADDR|g" "$MANIFEST_DIR/vault-connection.yaml" | kubectl apply -f -

echo "Applying VaultAuth (operator namespace)..."
kubectl apply -f "$MANIFEST_DIR/vault-auth.yaml"

echo "Applying VaultAuth (vault-test namespace)..."
kubectl apply -f "$MANIFEST_DIR/vault-auth-local.yaml"

# Wait a moment for auth to be ready
sleep 2

echo "Applying VaultStaticSecret..."
kubectl apply -f "$MANIFEST_DIR/vault-static-secret.yaml"

echo "Applying test pod..."
kubectl apply -f "$MANIFEST_DIR/test-pod-vso.yaml"

echo ""
echo -e "${GREEN}✓${NC} All VSO resources applied"
echo ""

# Wait for secret to sync
echo "Waiting for secret to sync (up to 60s)..."
for i in {1..12}; do
    if kubectl get secret myapp-config -n vault-test &>/dev/null; then
        echo -e "${GREEN}✓${NC} Kubernetes Secret 'myapp-config' created!"
        break
    fi
    echo "  Waiting... ($i/12)"
    sleep 5
done
echo ""

# Show VSO status
echo "VSO Resource Status:"
echo "--------------------"
echo ""
echo "VaultConnection:"
kubectl get vaultconnection -n vault-secrets-operator 2>/dev/null || echo "  (none found)"
echo ""
echo "VaultAuth (operator namespace):"
kubectl get vaultauth -n vault-secrets-operator 2>/dev/null || echo "  (none found)"
echo ""
echo "VaultAuth (vault-test namespace):"
kubectl get vaultauth -n vault-test 2>/dev/null || echo "  (none found)"
echo ""
echo "VaultStaticSecret:"
kubectl get vaultstaticsecret -n vault-test 2>/dev/null || echo "  (none found)"
echo ""
echo "Synced Kubernetes Secret:"
kubectl get secret myapp-config -n vault-test 2>/dev/null || echo "  (not yet synced)"
echo ""

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Vault Secrets Operator Deployed!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "VSO is now syncing secrets from Vault to Kubernetes Secrets."
echo ""
echo "How it works:"
echo "  1. VaultConnection → Points to your Vault cluster"
echo "  2. VaultAuth       → Authenticates using K8s auth method"
echo "  3. VaultStaticSecret → Defines which secrets to sync"
echo "  4. K8s Secret      → Created/updated automatically"
echo ""
echo "To verify:"
echo "  kubectl get secret myapp-config -n vault-test -o yaml"
echo "  kubectl exec test-pod-vso -n vault-test -- env | grep -E 'username|password|api_key'"
echo ""
echo "Next step: Run ./scripts/08-test-vso.sh"
