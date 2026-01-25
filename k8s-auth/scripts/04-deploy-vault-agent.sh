#!/bin/bash
# 04-deploy-vault-agent.sh
# Deploys the Vault Agent Injector to Minikube using Helm
# The injector enables automatic secret injection via pod annotations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIKUBE_PROFILE="vault-k8s"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "============================================"
echo "  Vault Agent Injector Deployment"
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

# Add HashiCorp Helm repo
echo "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update
echo -e "${GREEN}✓${NC} Helm repo updated"
echo ""

# Create vault namespace
echo "Creating vault namespace..."
kubectl create namespace vault 2>/dev/null || echo "Namespace 'vault' already exists"
echo ""

# Cleanup any failed Helm releases or orphaned resources
echo "Checking for existing Helm release..."
RELEASE_STATUS=$(helm status vault -n vault 2>/dev/null | grep "STATUS:" | awk '{print $2}' || echo "not-found")
if [ "$RELEASE_STATUS" = "failed" ]; then
    echo -e "${YELLOW}⚠${NC}  Found failed Helm release, cleaning up..."
    helm uninstall vault -n vault 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Failed release removed"
fi

# Remove orphaned MutatingWebhookConfiguration to avoid field manager conflicts
if kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg &>/dev/null; then
    if [ "$RELEASE_STATUS" = "not-found" ] || [ "$RELEASE_STATUS" = "failed" ]; then
        echo -e "${YELLOW}⚠${NC}  Found orphaned webhook configuration, removing..."
        kubectl delete mutatingwebhookconfiguration vault-agent-injector-cfg 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Orphaned webhook removed"
    fi
fi
echo ""

# Deploy Vault Agent Injector using Helm
# Note: The Helm chart creates its own ServiceAccount for the injector
echo "Deploying Vault Agent Injector..."
echo "----------------------------------"

# Create values file
VALUES_FILE="/tmp/vault-agent-values.yaml"
cat > "$VALUES_FILE" <<EOF
# Vault Agent Injector Helm Values
# We only deploy the injector, not a full Vault server

global:
  enabled: true
  externalVaultAddr: "${VAULT_ADDR}"

injector:
  enabled: true
  replicas: 1

  # Use the external Vault address
  externalVaultAddr: "${VAULT_ADDR}"

  # Auth method configuration
  authPath: "auth/kubernetes"

  # Resource limits for lab environment
  resources:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
      cpu: 100m

  # Webhook configuration
  webhook:
    failurePolicy: Ignore  # Don't block pods if injector fails

  # Log level for debugging
  logLevel: "info"

# Disable the Vault server - we're using external Vault
server:
  enabled: false

# Disable CSI provider
csi:
  enabled: false

# Disable UI
ui:
  enabled: false
EOF

echo "Helm values:"
cat "$VALUES_FILE"
echo ""

# Install or upgrade the Helm chart
helm upgrade --install vault hashicorp/vault \
    --namespace vault \
    --values "$VALUES_FILE" \
    --wait

echo ""
echo -e "${GREEN}✓${NC} Vault Agent Injector deployed"
echo ""

# Wait for injector to be ready
echo "Waiting for injector pod to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault-agent-injector -n vault --timeout=120s

echo ""
echo "Injector pod status:"
kubectl get pods -n vault
echo ""

# Verify the mutating webhook is registered
echo "Checking mutating webhook configuration..."
kubectl get mutatingwebhookconfiguration | grep vault || echo "Webhook not yet registered"
echo ""

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Vault Agent Injector Deployed!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "The injector is now watching for pods with these annotations:"
echo ""
echo "  vault.hashicorp.com/agent-inject: \"true\""
echo "  vault.hashicorp.com/role: \"test-role\""
echo "  vault.hashicorp.com/agent-inject-secret-<filename>: \"<secret-path>\""
echo ""
echo "Example:"
echo "  vault.hashicorp.com/agent-inject: \"true\""
echo "  vault.hashicorp.com/role: \"test-role\""
echo "  vault.hashicorp.com/agent-inject-secret-config.txt: \"secret/data/myapp/config\""
echo ""
echo "Next step: Run ./scripts/05-deploy-test-resources.sh"
