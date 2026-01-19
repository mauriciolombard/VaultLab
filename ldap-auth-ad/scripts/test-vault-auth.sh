#!/bin/bash
# Test Vault LDAP Authentication with Active Directory
# Usage: ./test-vault-auth.sh
# Requires: VAULT_ADDR environment variable set

set -e

if [ -z "$VAULT_ADDR" ]; then
    echo "ERROR: VAULT_ADDR environment variable is not set"
    echo "Usage: export VAULT_ADDR=http://<vault-nlb>:8200 && ./test-vault-auth.sh"
    exit 1
fi

TEST_PASSWORD=${1:-"Password123!"}

echo "============================================"
echo "Vault LDAP (Active Directory) Auth Test"
echo "============================================"
echo "VAULT_ADDR: $VAULT_ADDR"
echo ""

# Test 1: Check LDAP auth method is enabled
echo "Test 1: Verify LDAP auth method is enabled"
echo "--------------------------------------------"
vault auth list 2>/dev/null | grep ldap && echo "LDAP auth is enabled" || echo "LDAP auth NOT found"
echo ""

# Test 2: Read LDAP auth configuration
echo "Test 2: LDAP auth configuration"
echo "--------------------------------------------"
vault read auth/ldap/config 2>/dev/null || echo "Unable to read config (may need privileges)"
echo ""

# Test 3: Login as alice (Vault-Admins group)
echo "Test 3: Login as alice (Vault-Admins)"
echo "--------------------------------------------"
echo "Expected: Should receive ldap-admins policy"
ALICE_TOKEN=$(vault login -method=ldap -token-only username=alice password="$TEST_PASSWORD" 2>&1) && {
    echo "SUCCESS: alice logged in"
    echo "Token: ${ALICE_TOKEN:0:20}..."

    # Check token details
    VAULT_TOKEN=$ALICE_TOKEN vault token lookup 2>/dev/null | grep -E "policies|display_name|entity_id"
} || echo "FAILED: alice login failed - $ALICE_TOKEN"
echo ""

# Test 4: Login as bob (Vault-Users group)
echo "Test 4: Login as bob (Vault-Users)"
echo "--------------------------------------------"
echo "Expected: Should receive ldap-users policy"
BOB_TOKEN=$(vault login -method=ldap -token-only username=bob password="$TEST_PASSWORD" 2>&1) && {
    echo "SUCCESS: bob logged in"
    echo "Token: ${BOB_TOKEN:0:20}..."

    # Check token details
    VAULT_TOKEN=$BOB_TOKEN vault token lookup 2>/dev/null | grep -E "policies|display_name|entity_id"
} || echo "FAILED: bob login failed - $BOB_TOKEN"
echo ""

# Test 5: Login with UPN format (alice@domain)
echo "Test 5: Login with UPN format (alice@vaultlab.local)"
echo "--------------------------------------------"
vault login -method=ldap -token-only username=alice@vaultlab.local password="$TEST_PASSWORD" 2>&1 && \
    echo "SUCCESS: UPN login works" || echo "UPN login failed (may need upndomain config)"
echo ""

# Test 6: Test policy enforcement (alice - admin)
echo "Test 6: Test alice's permissions (ldap-admins)"
echo "--------------------------------------------"
if [ -n "$ALICE_TOKEN" ] && [[ ! "$ALICE_TOKEN" == *"error"* ]]; then
    VAULT_TOKEN=$ALICE_TOKEN vault secrets list 2>/dev/null && \
        echo "SUCCESS: alice can list secrets engines" || \
        echo "alice cannot list secrets (check policy)"
else
    echo "SKIPPED: alice token not available"
fi
echo ""

# Test 7: Test policy enforcement (bob - user)
echo "Test 7: Test bob's permissions (ldap-users)"
echo "--------------------------------------------"
if [ -n "$BOB_TOKEN" ] && [[ ! "$BOB_TOKEN" == *"error"* ]]; then
    VAULT_TOKEN=$BOB_TOKEN vault secrets list 2>/dev/null && \
        echo "bob can list secrets (unexpected - check policy)" || \
        echo "EXPECTED: bob cannot list secrets engines (read-only policy)"
else
    echo "SKIPPED: bob token not available"
fi
echo ""

# Test 8: Login with wrong password
echo "Test 8: Login with wrong password (should fail)"
echo "--------------------------------------------"
vault login -method=ldap username=alice password=wrongpassword 2>&1 && \
    echo "ERROR: Should have failed!" || echo "EXPECTED: Login failed (correct behavior)"
echo ""

# Test 9: List LDAP groups configured in Vault
echo "Test 9: List LDAP group mappings in Vault"
echo "--------------------------------------------"
vault list auth/ldap/groups 2>/dev/null || echo "Unable to list groups (may need privileges)"
echo ""

# Test 10: Read specific group mapping
echo "Test 10: Read Vault-Admins group mapping"
echo "--------------------------------------------"
vault read auth/ldap/groups/Vault-Admins 2>/dev/null || echo "Unable to read group (may need privileges)"
echo ""

echo "============================================"
echo "Vault LDAP (AD) Auth Test Complete!"
echo "============================================"
echo ""
echo "If tests failed, common issues:"
echo "1. AD server still initializing (wait 10-15 min after deploy)"
echo "2. Vault cannot reach AD (check security groups)"
echo "3. Service account credentials incorrect"
echo "4. Group names are case-sensitive (Vault-Admins vs vault-admins)"
