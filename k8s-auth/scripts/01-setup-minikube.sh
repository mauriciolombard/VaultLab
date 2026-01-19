#!/bin/bash
# 01-setup-minikube.sh
# Sets up a Minikube cluster for Vault Kubernetes authentication testing
# This script checks prerequisites and starts Minikube with the required configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "  Minikube Setup for Vault K8s Auth"
echo "============================================"
echo ""

# Function to check if a command exists
check_command() {
    local cmd=$1
    local install_hint=$2
    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $cmd is installed: $(command -v "$cmd")"
        return 0
    else
        echo -e "${RED}✗${NC} $cmd is NOT installed"
        echo "  Install with: $install_hint"
        return 1
    fi
}

# Prerequisites check
echo "Checking prerequisites..."
echo "------------------------"
MISSING_DEPS=0

check_command "minikube" "brew install minikube" || MISSING_DEPS=1
check_command "kubectl" "brew install kubectl" || MISSING_DEPS=1
check_command "helm" "brew install helm" || MISSING_DEPS=1
check_command "ngrok" "brew install ngrok" || MISSING_DEPS=1
check_command "vault" "brew install vault" || MISSING_DEPS=1
check_command "jq" "brew install jq" || MISSING_DEPS=1

echo ""

if [ $MISSING_DEPS -eq 1 ]; then
    echo -e "${RED}ERROR: Missing dependencies. Please install them and re-run this script.${NC}"
    exit 1
fi

echo -e "${GREEN}All prerequisites are installed!${NC}"
echo ""

# Check if Minikube is already running
echo "Checking Minikube status..."
echo "---------------------------"
if minikube status &> /dev/null; then
    echo -e "${YELLOW}Minikube is already running.${NC}"
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing Minikube cluster..."
        minikube delete
    else
        echo "Using existing Minikube cluster."
        echo ""
        echo "Current cluster info:"
        kubectl cluster-info
        echo ""
        echo -e "${GREEN}Minikube is ready!${NC}"
        echo ""
        echo "Next step: Run ./scripts/02-setup-ngrok.sh"
        exit 0
    fi
fi

# Start Minikube
echo ""
echo "Starting Minikube cluster..."
echo "----------------------------"

# Start with docker driver (most common) and expose API server
minikube start \
    --driver=docker \
    --memory=4096 \
    --cpus=2 \
    --kubernetes-version=v1.29.0 \
    --extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/sa.key \
    --extra-config=apiserver.service-account-issuer=https://kubernetes.default.svc.cluster.local

echo ""
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo ""
echo "Cluster info:"
echo "-------------"
kubectl cluster-info
echo ""

echo "Nodes:"
kubectl get nodes
echo ""

# Get API server URL
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "Kubernetes API Server: $API_SERVER"
echo ""

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Minikube is ready!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next step: Run ./scripts/02-setup-ngrok.sh"
echo "This will create a tunnel to expose the Kubernetes API for Vault."
