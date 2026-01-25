#!/bin/bash
# 02-setup-ngrok.sh
# Sets up ngrok HTTP tunnel to expose Minikube's Kubernetes API to Vault
# Vault needs to reach the K8s API for TokenReview validation
#
# Uses HTTP tunnel (free tier, no credit card required)
# Note: TCP tunnels require card verification, but HTTP tunnels do not

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIKUBE_PROFILE="vault-k8s"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

LOG_FILE="/tmp/ngrok-k8s.log"
URL_FILE="/tmp/ngrok-k8s-url.txt"

echo "============================================"
echo "  ngrok HTTP Tunnel Setup for K8s API"
echo "============================================"
echo ""

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo -e "${RED}ERROR: ngrok is not installed${NC}"
    echo "Install with: brew install ngrok"
    exit 1
fi
echo -e "${GREEN}✓${NC} ngrok is installed"

# Check if ngrok is configured with an authtoken
echo "Checking ngrok authentication..."
NGROK_AUTHENTICATED=false

# Check multiple possible config locations
NGROK_CONFIG_PATHS=(
    "$HOME/.config/ngrok/ngrok.yml"
    "$HOME/Library/Application Support/ngrok/ngrok.yml"
    "$HOME/.ngrok2/ngrok.yml"
)

for NGROK_CONFIG_PATH in "${NGROK_CONFIG_PATHS[@]}"; do
    if [ -f "$NGROK_CONFIG_PATH" ] && grep -q "authtoken:" "$NGROK_CONFIG_PATH" 2>/dev/null; then
        NGROK_AUTHENTICATED=true
        break
    fi
done

# Alternative check using ngrok config check
if ! $NGROK_AUTHENTICATED && ngrok config check &> /dev/null; then
    NGROK_AUTHENTICATED=true
fi

if ! $NGROK_AUTHENTICATED; then
    echo -e "${YELLOW}ngrok is not configured with an authtoken${NC}"
    echo ""
    echo "You need an ngrok authtoken to create tunnels (free signup)."
    echo "1. Sign up for free at: https://ngrok.com"
    echo "2. Get your authtoken from: https://dashboard.ngrok.com/get-started/your-authtoken"
    echo ""
    read -p "Enter your ngrok authtoken (or Ctrl+C to exit): " NGROK_TOKEN

    if [ -z "$NGROK_TOKEN" ]; then
        echo -e "${RED}ERROR: No authtoken provided${NC}"
        exit 1
    fi

    echo ""
    echo "Configuring ngrok with provided authtoken..."
    ngrok config add-authtoken "$NGROK_TOKEN"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} ngrok configured successfully"
    else
        echo -e "${RED}ERROR: Failed to configure ngrok${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} ngrok is authenticated"
fi

# Check if Minikube is running
echo "Checking Minikube status..."
if ! minikube status -p $MINIKUBE_PROFILE &> /dev/null; then
    echo -e "${RED}ERROR: Minikube is not running${NC}"
    echo "Run ./01-setup-minikube.sh first"
    exit 1
fi
echo -e "${GREEN}✓${NC} Minikube is running"
echo ""

# Get Minikube API server details
echo "Getting Kubernetes API server info..."
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
API_HOST=$(echo "$API_SERVER" | sed 's|https://||' | cut -d: -f1)
API_PORT=$(echo "$API_SERVER" | sed 's|https://||' | cut -d: -f2)

echo "API Server: $API_SERVER"
echo "Host: $API_HOST"
echo "Port: $API_PORT"
echo ""

# Kill any existing ngrok processes
echo "Checking for existing ngrok tunnels..."
if pgrep -x "ngrok" > /dev/null; then
    echo -e "${YELLOW}Stopping existing ngrok process...${NC}"
    pkill -x ngrok || true
    sleep 2
fi

# For Minikube with docker driver, determine the correct target
MINIKUBE_IP=$(minikube ip -p $MINIKUBE_PROFILE 2>/dev/null || echo "127.0.0.1")
echo "Minikube IP: $MINIKUBE_IP"

# Determine tunnel target based on API host
if [ "$API_HOST" = "127.0.0.1" ] || [ "$API_HOST" = "localhost" ]; then
    # Docker driver - API is on localhost
    TUNNEL_TARGET="https://${API_HOST}:${API_PORT}"
else
    # VM driver - API is on minikube IP
    TUNNEL_TARGET="https://${MINIKUBE_IP}:8443"
fi

echo ""
echo "============================================"
echo "  Starting ngrok HTTP tunnel..."
echo "============================================"
echo ""
echo "Tunnel target: $TUNNEL_TARGET"
echo ""
echo -e "${CYAN}Note: Using HTTP tunnel (free tier, no credit card required)${NC}"
echo ""

# Start ngrok HTTP tunnel in background
# The K8s API uses self-signed certs, so we need to allow insecure
echo "Starting ngrok in background..."
nohup ngrok http "$TUNNEL_TARGET" --log=stdout > "$LOG_FILE" 2>&1 &
NGROK_PID=$!

echo "ngrok started with PID: $NGROK_PID"
echo ""

# Wait for ngrok to establish the tunnel
echo "Waiting for tunnel to establish..."
sleep 5

# Get the public URL from ngrok API
echo "Getting tunnel URL..."
NGROK_URL=""
for i in {1..10}; do
    NGROK_API_RESPONSE=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null || echo "{}")
    NGROK_URL=$(echo "$NGROK_API_RESPONSE" | jq -r '.tunnels[0].public_url // empty' 2>/dev/null)

    if [ -n "$NGROK_URL" ]; then
        break
    fi

    # Check if ngrok is still running
    if ! ps -p "$NGROK_PID" > /dev/null 2>&1; then
        echo -e "${RED}ERROR: ngrok process died unexpectedly${NC}"
        echo ""
        echo "Log output:"
        tail -20 "$LOG_FILE"
        exit 1
    fi

    echo "  Attempt $i/10 - waiting..."
    sleep 2
done

if [ -z "$NGROK_URL" ]; then
    echo -e "${RED}ERROR: Could not get ngrok tunnel URL${NC}"
    echo ""
    echo "Check ngrok logs: cat $LOG_FILE"
    echo "Or open ngrok dashboard: http://localhost:4040"
    echo ""
    echo "Recent log output:"
    tail -20 "$LOG_FILE"
    exit 1
fi

# ngrok HTTP tunnels provide HTTPS URLs directly
KUBERNETES_HOST="$NGROK_URL"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ngrok Tunnel Established!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${CYAN}IMPORTANT: Save this URL for the next step!${NC}"
echo ""
echo "  ngrok URL:        $NGROK_URL"
echo "  KUBERNETES_HOST:  $KUBERNETES_HOST"
echo ""
echo "ngrok Dashboard: http://localhost:4040"
echo "ngrok PID: $NGROK_PID (kill with: kill $NGROK_PID)"
echo "Logs: $LOG_FILE"
echo ""

# Save the URL to a file for other scripts to use
echo "$KUBERNETES_HOST" > "$URL_FILE"
echo "URL saved to $URL_FILE"
echo ""

echo "============================================"
echo "  Next Steps"
echo "============================================"
echo ""
echo "1. Export the required environment variables:"
echo ""
echo "   export VAULT_ADDR=\"http://<your-vault-nlb>:8200\""
echo "   export VAULT_TOKEN=\"<your-root-token>\""
echo "   export KUBERNETES_HOST=\"$KUBERNETES_HOST\""
echo ""
echo "2. Run: ./03-configure-vault-auth.sh"
echo ""
echo -e "${YELLOW}NOTE: Keep this terminal open to maintain the tunnel.${NC}"
echo "      If you close it, you'll need to re-run this script"
echo "      and update the Vault configuration with the new URL."
echo ""
echo "To stop the tunnel: kill $NGROK_PID"
