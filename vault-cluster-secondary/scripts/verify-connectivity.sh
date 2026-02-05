#!/bin/bash
# Verify cross-cluster connectivity for replication
# Usage: ./verify-connectivity.sh

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}+------------------------------------------------------------+${NC}"
echo -e "${BLUE}|      Verify Cross-Cluster Connectivity                     |${NC}"
echo -e "${BLUE}+------------------------------------------------------------+${NC}"

# Get IPs from Terraform outputs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIMARY_DIR="${SCRIPT_DIR}/../../awskms-autounseal"
SECONDARY_DIR="${SCRIPT_DIR}/.."

echo -e "\n${YELLOW}Fetching cluster IPs from Terraform...${NC}"

# Get primary cluster IPs
if [ -d "$PRIMARY_DIR" ]; then
    cd "$PRIMARY_DIR"
    PRIMARY_IPS=$(terraform output -json vault_instance_ips 2>/dev/null | jq -r '.[].private_ip' 2>/dev/null || echo "")
    cd - > /dev/null
else
    echo -e "${RED}Primary cluster directory not found at $PRIMARY_DIR${NC}"
    PRIMARY_IPS=""
fi

# Get secondary cluster IPs
if [ -d "$SECONDARY_DIR" ]; then
    cd "$SECONDARY_DIR"
    SECONDARY_IPS=$(terraform output -json vault_instance_ips 2>/dev/null | jq -r '.[].private_ip' 2>/dev/null || echo "")
    cd - > /dev/null
else
    echo -e "${RED}Secondary cluster directory not found at $SECONDARY_DIR${NC}"
    SECONDARY_IPS=""
fi

if [ -z "$PRIMARY_IPS" ]; then
    echo -e "${RED}Could not fetch primary IPs. Ensure terraform has been applied in awskms-autounseal/.${NC}"
fi

if [ -z "$SECONDARY_IPS" ]; then
    echo -e "${RED}Could not fetch secondary IPs. Ensure terraform has been applied in vault-cluster-secondary/.${NC}"
fi

if [ -n "$PRIMARY_IPS" ]; then
    echo -e "${GREEN}Primary IPs: $(echo $PRIMARY_IPS | tr '\n' ' ')${NC}"
fi
if [ -n "$SECONDARY_IPS" ]; then
    echo -e "${GREEN}Secondary IPs: $(echo $SECONDARY_IPS | tr '\n' ' ')${NC}"
fi

echo -e "\n${YELLOW}Testing connectivity:${NC}"
echo -e "${YELLOW}These commands must be run FROM INSIDE the EC2 nodes (SSH in first).${NC}"
echo ""
echo -e "${BLUE}Get SSH commands for each cluster:${NC}"
echo "  cd awskms-autounseal && terraform output ssh_connection_commands"
echo "  cd vault-cluster-secondary && terraform output ssh_connection_commands"
echo ""
echo -e "${BLUE}Step 1: SSH into a PRIMARY node, then test connectivity TO secondary:${NC}"
for ip in $SECONDARY_IPS; do
    echo "  nc -zv $ip 8200 && nc -zv $ip 8201"
done

echo ""
echo -e "${BLUE}Step 2: SSH into a SECONDARY node, then test connectivity TO primary:${NC}"
for ip in $PRIMARY_IPS; do
    echo "  nc -zv $ip 8200 && nc -zv $ip 8201"
done

echo -e "\n${YELLOW}Expected result: Connection succeeded${NC}"
echo "If connection fails, check:"
echo "  1. VPC peering connection is active"
echo "  2. Security group rules allow 8200/8201 from peer VPC"
echo "  3. Route tables have routes to peer VPC"

echo -e "\n${BLUE}Additional diagnostic commands:${NC}"
echo ""
echo "# Check VPC peering status:"
echo "  aws ec2 describe-vpc-peering-connections --query 'VpcPeeringConnections[*].[VpcPeeringConnectionId,Status.Code]'"
echo ""
echo "# Check replication status on both clusters:"
echo "  VAULT_ADDR=\$PRIMARY_VAULT_ADDR vault read sys/replication/status"
echo "  VAULT_ADDR=\$SECONDARY_VAULT_ADDR vault read sys/replication/status"
