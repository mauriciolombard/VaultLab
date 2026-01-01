#!/bin/bash
# Test script for LDAP secrets engine library sets (service account check-out)
# Run this on the Vault instance after initialization

set -e

echo "=== LDAP Secrets Engine Library Set Test ==="
echo ""

# Check if VAULT_TOKEN is set
if [ -z "$VAULT_TOKEN" ]; then
    echo "ERROR: VAULT_TOKEN not set. Please export VAULT_TOKEN first."
    exit 1
fi

# Source environment (if running on Vault instance)
[ -f /etc/profile.d/vault.sh ] && source /etc/profile.d/vault.sh
[ -f /etc/profile.d/ldap.sh ] && source /etc/profile.d/ldap.sh

LDAP_HOST=${LDAP_HOST:-localhost}
LDAP_BASE_DN=${LDAP_BASE_DN:-"dc=vaultlab,dc=local"}
LDAP_BIND_PASS=${LDAP_BIND_PASS:-"admin123"}

echo "Using LDAP_HOST: $LDAP_HOST"
echo "Using LDAP_BASE_DN: $LDAP_BASE_DN"
echo ""

# Ensure LDAP secrets engine is enabled
echo "1. Enabling LDAP secrets engine..."
vault secrets enable ldap || echo "   (already enabled)"

# Configure LDAP secrets engine
echo "2. Configuring LDAP secrets engine..."
vault write ldap/config \
    binddn="cn=admin,$LDAP_BASE_DN" \
    bindpass="$LDAP_BIND_PASS" \
    url="ldap://$LDAP_HOST:389" \
    userdn="ou=services,$LDAP_BASE_DN" \
    userattr="uid" \
    schema="openldap"

# Create a library set
echo "3. Creating library set 'app-service-accounts'..."
vault write ldap/library/app-service-accounts \
    service_account_names="svc-app1,svc-app2" \
    ttl="1h" \
    max_ttl="24h" \
    disable_check_in_enforcement=false

# Check out a service account
echo "4. Checking out a service account..."
CHECKOUT=$(vault write -format=json ldap/library/app-service-accounts/check-out)
echo "$CHECKOUT" | jq .

SERVICE_ACCOUNT=$(echo "$CHECKOUT" | jq -r '.data.service_account_name')
PASSWORD=$(echo "$CHECKOUT" | jq -r '.data.password')

echo ""
echo "5. Checked out: $SERVICE_ACCOUNT"

echo ""
echo "6. Testing LDAP bind with checked-out account..."
ldapwhoami -x -H ldap://$LDAP_HOST:389 \
    -D "uid=$SERVICE_ACCOUNT,ou=services,$LDAP_BASE_DN" \
    -w "$PASSWORD" && echo "   SUCCESS: LDAP bind successful!" || echo "   FAILED: LDAP bind failed"

echo ""
echo "7. Checking library status..."
vault read ldap/library/app-service-accounts/status

echo ""
echo "8. Checking in the service account..."
vault write ldap/library/app-service-accounts/check-in \
    service_account_names="$SERVICE_ACCOUNT"

echo ""
echo "9. Verifying check-in (should show available)..."
vault read ldap/library/app-service-accounts/status

echo ""
echo "=== Library Set Test Complete ==="
