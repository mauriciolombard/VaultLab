#!/bin/bash
# Test Active Directory LDAP connectivity and configuration
# Usage: ./test-ad.sh <AD_SERVER_IP>

set -e

AD_SERVER=${1:-$(terraform output -raw ad_server_public_ip 2>/dev/null || echo "localhost")}
LDAP_PORT=${2:-389}
DOMAIN=${3:-"vaultlab.local"}
SERVICE_ACCOUNT="vault-svc"
SERVICE_PASS=${4:-"VaultBind123!"}

# Convert domain to AD-style base DN (vaultlab.local -> DC=vaultlab,DC=local)
IFS='.' read -ra DOMAIN_PARTS <<< "$DOMAIN"
BASE_DN="DC=${DOMAIN_PARTS[0]},DC=${DOMAIN_PARTS[1]}"

echo "============================================"
echo "Active Directory LDAP Test Script"
echo "============================================"
echo "Server: $AD_SERVER:$LDAP_PORT"
echo "Domain: $DOMAIN"
echo "Base DN: $BASE_DN"
echo ""

# Test 1: Check LDAP port connectivity
echo "Test 1: Check LDAP port connectivity"
echo "--------------------------------------------"
nc -zv $AD_SERVER $LDAP_PORT 2>&1 || echo "WARNING: Cannot connect to LDAP port"
echo ""

# Test 2: Anonymous RootDSE query (should work on AD)
echo "Test 2: Anonymous RootDSE query"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$AD_SERVER:$LDAP_PORT -b "" -s base "(objectClass=*)" \
    defaultNamingContext dnsHostName 2>&1 || echo "RootDSE query failed"
echo ""

# Test 3: Bind as service account
echo "Test 3: Bind as service account (vault-svc)"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$AD_SERVER:$LDAP_PORT \
    -D "${SERVICE_ACCOUNT}@${DOMAIN}" \
    -w "$SERVICE_PASS" \
    -b "$BASE_DN" \
    "(objectClass=top)" dn 2>&1 | head -20 || echo "Service account bind failed"
echo ""

# Test 4: Search for users
echo "Test 4: List AD users"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$AD_SERVER:$LDAP_PORT \
    -D "${SERVICE_ACCOUNT}@${DOMAIN}" \
    -w "$SERVICE_PASS" \
    -b "CN=Users,$BASE_DN" \
    "(objectClass=user)" sAMAccountName cn 2>&1 | grep -E "^dn:|sAMAccountName:|^cn:" || echo "User search failed"
echo ""

# Test 5: Search for groups
echo "Test 5: List AD security groups"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$AD_SERVER:$LDAP_PORT \
    -D "${SERVICE_ACCOUNT}@${DOMAIN}" \
    -w "$SERVICE_PASS" \
    -b "CN=Users,$BASE_DN" \
    "(&(objectClass=group)(|(cn=Vault-Admins)(cn=Vault-Users)))" cn member 2>&1 || echo "Group search failed"
echo ""

# Test 6: Bind as test user (alice)
echo "Test 6: Bind as user 'alice'"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$AD_SERVER:$LDAP_PORT \
    -D "alice@${DOMAIN}" \
    -w "Password123!" \
    -b "CN=Users,$BASE_DN" \
    "(sAMAccountName=alice)" sAMAccountName cn memberOf 2>&1 && \
    echo "SUCCESS: alice can bind" || echo "FAILED: alice cannot bind"
echo ""

# Test 7: Check alice's group membership via memberOf
echo "Test 7: Check alice's group membership"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$AD_SERVER:$LDAP_PORT \
    -D "${SERVICE_ACCOUNT}@${DOMAIN}" \
    -w "$SERVICE_PASS" \
    -b "CN=Users,$BASE_DN" \
    "(sAMAccountName=alice)" memberOf 2>&1 | grep -i "vault" || echo "No Vault groups found for alice"
echo ""

# Test 8: Test group filter (same as Vault uses)
echo "Test 8: Test Vault's group filter for alice"
echo "--------------------------------------------"
# Get alice's DN first
ALICE_DN=$(ldapsearch -x -H ldap://$AD_SERVER:$LDAP_PORT \
    -D "${SERVICE_ACCOUNT}@${DOMAIN}" \
    -w "$SERVICE_PASS" \
    -b "CN=Users,$BASE_DN" \
    "(sAMAccountName=alice)" dn 2>/dev/null | grep "^dn:" | sed 's/^dn: //')
echo "Alice DN: $ALICE_DN"

if [ -n "$ALICE_DN" ]; then
    ldapsearch -x -H ldap://$AD_SERVER:$LDAP_PORT \
        -D "${SERVICE_ACCOUNT}@${DOMAIN}" \
        -w "$SERVICE_PASS" \
        -b "CN=Users,$BASE_DN" \
        "(&(objectClass=group)(member:1.2.840.113556.1.4.1941:=$ALICE_DN))" cn 2>&1 || echo "Group filter search failed"
fi
echo ""

echo "============================================"
echo "Active Directory LDAP Test Complete!"
echo "============================================"
echo ""
echo "If tests failed, check:"
echo "1. AD server has finished setup (can take 10-15 min)"
echo "2. Security groups allow LDAP port 389"
echo "3. Service account credentials are correct"
