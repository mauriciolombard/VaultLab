#!/bin/bash
# 03-configure-vault-auth.sh
# Configures Vault's Kubernetes auth backend to use the ngrok tunnel
# This script can be run via CLI (without Terraform) for quick setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIKUBE_PROFILE="vault-k8s"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "============================================"
echo "  Vault Kubernetes Auth Configuration"
echo "============================================"
echo ""

# Check required environment variables
echo "Checking environment variables..."
echo "---------------------------------"

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
echo -e "${GREEN}✓${NC} VAULT_TOKEN: [set]"

# Try to get KUBERNETES_HOST from file if not set
if [ -z "$KUBERNETES_HOST" ]; then
    if [ -f /tmp/ngrok-k8s-url.txt ]; then
        KUBERNETES_HOST=$(cat /tmp/ngrok-k8s-url.txt)
        echo -e "${YELLOW}!${NC} KUBERNETES_HOST loaded from /tmp/ngrok-k8s-url.txt"
    else
        echo -e "${RED}ERROR: KUBERNETES_HOST is not set${NC}"
        echo "Export it with: export KUBERNETES_HOST=\"https://<ngrok-url>\""
        echo "Or run ./scripts/02-setup-ngrok.sh first"
        exit 1
    fi
fi
echo -e "${GREEN}✓${NC} KUBERNETES_HOST: $KUBERNETES_HOST"
echo ""

# Check Vault connectivity
echo "Checking Vault connectivity..."
if ! vault status &> /dev/null; then
    echo -e "${RED}ERROR: Cannot connect to Vault at $VAULT_ADDR${NC}"
    echo "Make sure Vault is running and accessible"
    exit 1
fi
echo -e "${GREEN}✓${NC} Vault is accessible"
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

# Create the vault-auth service account in Kubernetes
echo "Creating vault-auth ServiceAccount in Kubernetes..."
echo "----------------------------------------------------"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-auth-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: vault-auth
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: kube-system
EOF

echo -e "${GREEN}✓${NC} ServiceAccount and ClusterRoleBinding created"
echo ""

# Wait for the token to be generated
echo "Waiting for service account token..."
sleep 3

# Get the token reviewer JWT
echo "Getting token reviewer JWT..."
TOKEN_REVIEWER_JWT=$(kubectl get secret vault-auth-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)

if [ -z "$TOKEN_REVIEWER_JWT" ]; then
    echo -e "${RED}ERROR: Could not get token reviewer JWT${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Token reviewer JWT obtained"
echo ""

# Get Kubernetes CA certificate
echo "Getting Kubernetes CA certificate..."
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)
echo -e "${GREEN}✓${NC} CA certificate obtained"
echo ""

# Enable Kubernetes auth in Vault
echo "Enabling Kubernetes auth in Vault..."
echo "-------------------------------------"

# Check if already enabled
if vault auth list | grep -q "^kubernetes/"; then
    echo -e "${YELLOW}!${NC} Kubernetes auth already enabled, updating configuration..."
else
    vault auth enable kubernetes
    echo -e "${GREEN}✓${NC} Kubernetes auth enabled"
fi
echo ""

# Configure Kubernetes auth
echo "Configuring Kubernetes auth backend..."
vault write auth/kubernetes/config \
    kubernetes_host="$KUBERNETES_HOST" \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    disable_iss_validation=true \
    disable_local_ca_jwt=true

echo -e "${GREEN}✓${NC} Kubernetes auth configured"
echo ""

# Create the test policy
echo "Creating k8s-test-policy..."
vault policy write k8s-test-policy - <<EOF
# Vault Policy for Kubernetes-authenticated pods
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/myapp/*" {
  capabilities = ["read", "list"]
}

path "secret/myapp/*" {
  capabilities = ["read", "list"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/kubernetes/config" {
  capabilities = ["read"]
}

path "auth/kubernetes/role/*" {
  capabilities = ["read", "list"]
}

path "sys/health" {
  capabilities = ["read"]
}
EOF
echo -e "${GREEN}✓${NC} Policy created"
echo ""

# Create the test role
echo "Creating test-role..."
vault write auth/kubernetes/role/test-role \
    bound_service_account_names=vault-sa \
    bound_service_account_namespaces=vault-test \
    policies=k8s-test-policy,default \
    ttl=1h \
    max_ttl=24h

echo -e "${GREEN}✓${NC} Role created"
echo ""

# Create a test secret
echo "Creating test secret at secret/myapp/config..."
# Enable KV v2 if not already enabled
vault secrets enable -path=secret -version=2 kv 2>/dev/null || true
# Wait for KV v2 backend upgrade to complete (avoids "Waiting for the primary to upgrade" error)
sleep 3
vault kv put secret/myapp/config \
    username="testuser" \
    password="testpassword123" \
    api_key="sk-test-12345"

echo -e "${GREEN}✓${NC} Test secret created"
echo ""

# Verify configuration
echo "============================================"
echo "  Verifying Configuration"
echo "============================================"
echo ""

echo "Auth methods:"
vault auth list
echo ""

echo "Kubernetes auth config:"
vault read auth/kubernetes/config
echo ""

echo "Kubernetes auth roles:"
vault list auth/kubernetes/role
echo ""

echo "test-role details:"
vault read auth/kubernetes/role/test-role
echo ""

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Vault Kubernetes Auth Configured!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Configuration Summary:"
echo "  Auth Path:        kubernetes"
echo "  Kubernetes Host:  $KUBERNETES_HOST"
echo "  Role:             test-role"
echo "  Bound SA:         vault-sa"
echo "  Bound Namespace:  vault-test"
echo "  Policies:         k8s-test-policy, default"
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/04-deploy-vault-agent.sh"
echo "  2. Run: ./scripts/05-deploy-test-resources.sh"
echo "  3. Run: ./scripts/test-k8s-auth.sh"
