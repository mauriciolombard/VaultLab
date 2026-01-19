#!/bin/bash
# 08-test-vso.sh
# Tests the Vault Secrets Operator (VSO) integration
# Validates that secrets are properly synced from Vault to Kubernetes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

test_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "============================================"
echo "  Vault Secrets Operator Test Suite"
echo "============================================"
echo ""

# Test 1: VSO Controller Running
echo "Test 1: VSO Controller Running"
echo "-------------------------------"
if kubectl get pods -n vault-secrets-operator -l app.kubernetes.io/name=vault-secrets-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    test_pass "VSO controller is running"
else
    test_fail "VSO controller is not running"
fi
echo ""

# Test 2: VaultConnection Status
echo "Test 2: VaultConnection Status"
echo "-------------------------------"
VC_STATUS=$(kubectl get vaultconnection vault-connection -n vault-secrets-operator -o jsonpath='{.status.valid}' 2>/dev/null || echo "not-found")
if [ "$VC_STATUS" = "true" ]; then
    test_pass "VaultConnection is valid"
else
    test_fail "VaultConnection status: $VC_STATUS"
    echo "  Debug: kubectl describe vaultconnection vault-connection -n vault-secrets-operator"
fi
echo ""

# Test 3: VaultAuth Status
echo "Test 3: VaultAuth Status"
echo "------------------------"
VA_STATUS=$(kubectl get vaultauth vault-auth -n vault-secrets-operator -o jsonpath='{.status.valid}' 2>/dev/null || echo "not-found")
if [ "$VA_STATUS" = "true" ]; then
    test_pass "VaultAuth is valid"
else
    test_fail "VaultAuth status: $VA_STATUS"
    echo "  Debug: kubectl describe vaultauth vault-auth -n vault-secrets-operator"
fi
echo ""

# Test 4: VaultStaticSecret Synced
echo "Test 4: VaultStaticSecret Sync Status"
echo "--------------------------------------"
VSS_SYNCED=$(kubectl get vaultstaticsecret myapp-config-sync -n vault-test -o jsonpath='{.status.secretMAC}' 2>/dev/null || echo "")
if [ -n "$VSS_SYNCED" ]; then
    test_pass "VaultStaticSecret has synced (secretMAC present)"
else
    test_fail "VaultStaticSecret has not synced"
    echo "  Debug: kubectl describe vaultstaticsecret myapp-config-sync -n vault-test"
fi
echo ""

# Test 5: Kubernetes Secret Created
echo "Test 5: Kubernetes Secret Created"
echo "----------------------------------"
if kubectl get secret myapp-config -n vault-test &>/dev/null; then
    test_pass "Kubernetes Secret 'myapp-config' exists"
else
    test_fail "Kubernetes Secret 'myapp-config' not found"
fi
echo ""

# Test 6: Secret Contains Expected Keys
echo "Test 6: Secret Contains Expected Keys"
echo "--------------------------------------"
SECRET_KEYS=$(kubectl get secret myapp-config -n vault-test -o jsonpath='{.data}' 2>/dev/null | grep -o '"[^"]*":' | tr -d '":' | sort | tr '\n' ' ')
if echo "$SECRET_KEYS" | grep -q "username" && echo "$SECRET_KEYS" | grep -q "password"; then
    test_pass "Secret contains username and password keys"
    echo "  Keys found: $SECRET_KEYS"
else
    test_fail "Secret missing expected keys"
    echo "  Expected: username, password, api_key"
    echo "  Found: $SECRET_KEYS"
fi
echo ""

# Test 7: Secret Values Match Vault
echo "Test 7: Secret Values Match Vault"
echo "----------------------------------"
K8S_USERNAME=$(kubectl get secret myapp-config -n vault-test -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
VAULT_USERNAME=$(vault kv get -field=username secret/myapp/config 2>/dev/null || echo "")
if [ -n "$K8S_USERNAME" ] && [ "$K8S_USERNAME" = "$VAULT_USERNAME" ]; then
    test_pass "K8s Secret matches Vault secret (username verified)"
else
    test_fail "K8s Secret does not match Vault secret"
    echo "  K8s value: $K8S_USERNAME"
    echo "  Vault value: $VAULT_USERNAME"
fi
echo ""

# Test 8: Test Pod Running
echo "Test 8: Test Pod Running"
echo "------------------------"
POD_STATUS=$(kubectl get pod test-pod-vso -n vault-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "not-found")
if [ "$POD_STATUS" = "Running" ]; then
    test_pass "test-pod-vso is running"
else
    test_fail "test-pod-vso status: $POD_STATUS"
fi
echo ""

# Test 9: Pod Can Read Secret via Environment
echo "Test 9: Pod Reads Secret via Environment"
echo "-----------------------------------------"
# Note: envFrom creates env vars with same names as secret keys (lowercase)
POD_USERNAME=$(kubectl exec test-pod-vso -n vault-test -- printenv username 2>/dev/null || echo "")
if [ -n "$POD_USERNAME" ]; then
    test_pass "Pod can read username from environment"
    echo "  username: $POD_USERNAME"
else
    test_fail "Pod cannot read username from environment"
fi
echo ""

# Test 10: Pod Can Read Secret via Volume
echo "Test 10: Pod Reads Secret via Volume Mount"
echo "-------------------------------------------"
VOLUME_USERNAME=$(kubectl exec test-pod-vso -n vault-test -- cat /etc/secrets/username 2>/dev/null || echo "")
if [ -n "$VOLUME_USERNAME" ]; then
    test_pass "Pod can read username from volume mount"
else
    test_fail "Pod cannot read from volume mount"
fi
echo ""

# Test 11: VSO Labels on Secret
echo "Test 11: VSO Labels on Managed Secret"
echo "--------------------------------------"
MANAGED_BY=$(kubectl get secret myapp-config -n vault-test -o jsonpath='{.metadata.labels.managed-by}' 2>/dev/null || echo "")
if [ "$MANAGED_BY" = "vault-secrets-operator" ]; then
    test_pass "Secret has correct managed-by label"
else
    test_fail "Secret missing managed-by label"
    echo "  Expected: vault-secrets-operator"
    echo "  Found: $MANAGED_BY"
fi
echo ""

# Summary
echo "============================================"
echo "  Test Results"
echo "============================================"
echo ""
echo -e "  ${GREEN}Passed:${NC} $PASS_COUNT"
echo -e "  ${RED}Failed:${NC} $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo ""
    echo "VSO is working correctly. Secrets are being synced from Vault to Kubernetes."
    echo ""
    echo "Key differences from Agent Injector:"
    echo "  - Secrets stored as native K8s Secrets (not ephemeral)"
    echo "  - No sidecar container needed per pod"
    echo "  - Pods consume secrets via standard K8s patterns (envFrom, volumeMount)"
    echo "  - Central operator manages all secret syncing"
else
    echo -e "${RED}Some tests failed.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check VSO controller logs:"
    echo "     kubectl logs -l app.kubernetes.io/name=vault-secrets-operator -n vault-secrets-operator"
    echo ""
    echo "  2. Check VaultAuth status (common issues: wrong role, auth path):"
    echo "     kubectl describe vaultauth vault-auth -n vault-secrets-operator"
    echo ""
    echo "  3. Check VaultStaticSecret events:"
    echo "     kubectl describe vaultstaticsecret myapp-config-sync -n vault-test"
    echo ""
    echo "  4. Verify Vault role exists:"
    echo "     vault read auth/kubernetes/role/vso-role"
fi

exit $FAIL_COUNT
