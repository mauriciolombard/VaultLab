#!/bin/bash
# test-k8s-auth.sh
# End-to-end test of Vault Kubernetes authentication
# Tests both manual CLI auth and Vault Agent injector

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
    echo -e "${YELLOW}WARN${NC}: $1"
}

echo "============================================"
echo "  Vault Kubernetes Auth - Test Suite"
echo "============================================"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
echo "-------------------------"

if [ -z "$VAULT_ADDR" ]; then
    fail "VAULT_ADDR is not set"
    exit 1
fi
pass "VAULT_ADDR is set: $VAULT_ADDR"

if ! vault status &> /dev/null; then
    fail "Cannot connect to Vault"
    exit 1
fi
pass "Vault is accessible"

if ! minikube status &> /dev/null; then
    fail "Minikube is not running"
    exit 1
fi
pass "Minikube is running"

echo ""

# Test 1: Kubernetes auth is enabled
echo "============================================"
echo "Test 1: Kubernetes auth method enabled"
echo "============================================"
if vault auth list | grep -q "^kubernetes/"; then
    pass "Kubernetes auth method is enabled"
else
    fail "Kubernetes auth method is NOT enabled"
fi
echo ""

# Test 2: Kubernetes auth config
echo "============================================"
echo "Test 2: Kubernetes auth configuration"
echo "============================================"
echo "Reading auth/kubernetes/config..."
if vault read auth/kubernetes/config &> /dev/null; then
    pass "Kubernetes auth config is readable"
    vault read auth/kubernetes/config | grep -E "kubernetes_host|disable_"
else
    fail "Cannot read Kubernetes auth config"
fi
echo ""

# Test 3: test-role exists
echo "============================================"
echo "Test 3: test-role configuration"
echo "============================================"
if vault read auth/kubernetes/role/test-role &> /dev/null; then
    pass "test-role exists"
    vault read auth/kubernetes/role/test-role | grep -E "bound_service_account|policies|token_ttl"
else
    fail "test-role does NOT exist"
fi
echo ""

# Test 4: Test pods are running
echo "============================================"
echo "Test 4: Test pods status"
echo "============================================"
echo "Checking pods in vault-test namespace..."

if kubectl get pod test-pod-manual -n vault-test &> /dev/null; then
    POD_STATUS=$(kubectl get pod test-pod-manual -n vault-test -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        pass "test-pod-manual is Running"
    else
        warn "test-pod-manual status: $POD_STATUS"
    fi
else
    fail "test-pod-manual does not exist"
fi

if kubectl get pod test-pod-injector -n vault-test &> /dev/null; then
    POD_STATUS=$(kubectl get pod test-pod-injector -n vault-test -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        pass "test-pod-injector is Running"
    else
        warn "test-pod-injector status: $POD_STATUS"
    fi
else
    fail "test-pod-injector does not exist"
fi
echo ""

# Test 5: Manual authentication from pod
echo "============================================"
echo "Test 5: Manual authentication from pod"
echo "============================================"
echo "Executing vault login inside test-pod-manual..."

LOGIN_RESULT=$(kubectl exec test-pod-manual -n vault-test -- \
    vault write -format=json auth/kubernetes/login \
    role=test-role \
    jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token 2>&1) || true

if echo "$LOGIN_RESULT" | jq -e '.auth.client_token' &> /dev/null; then
    pass "Manual authentication successful"
    TOKEN=$(echo "$LOGIN_RESULT" | jq -r '.auth.client_token')
    POLICIES=$(echo "$LOGIN_RESULT" | jq -r '.auth.policies | join(", ")')
    echo "  Token: ${TOKEN:0:20}..."
    echo "  Policies: $POLICIES"
else
    fail "Manual authentication failed"
    echo "  Error: $LOGIN_RESULT"
fi
echo ""

# Test 6: Token has correct policies
echo "============================================"
echo "Test 6: Token policy verification"
echo "============================================"
if [ -n "$TOKEN" ]; then
    LOOKUP_RESULT=$(kubectl exec test-pod-manual -n vault-test -- \
        sh -c "VAULT_TOKEN=$TOKEN vault token lookup -format=json" 2>&1) || true

    if echo "$LOOKUP_RESULT" | jq -e '.data.policies' &> /dev/null; then
        pass "Token lookup successful"
        POLICIES=$(echo "$LOOKUP_RESULT" | jq -r '.data.policies | join(", ")')
        echo "  Attached policies: $POLICIES"

        if echo "$POLICIES" | grep -q "k8s-test-policy"; then
            pass "k8s-test-policy is attached"
        else
            fail "k8s-test-policy is NOT attached"
        fi
    else
        fail "Token lookup failed"
    fi
else
    warn "Skipping - no token from previous test"
fi
echo ""

# Test 7: Secret access
echo "============================================"
echo "Test 7: Secret access verification"
echo "============================================"
if [ -n "$TOKEN" ]; then
    SECRET_RESULT=$(kubectl exec test-pod-manual -n vault-test -- \
        sh -c "VAULT_TOKEN=$TOKEN vault kv get -format=json secret/myapp/config" 2>&1) || true

    if echo "$SECRET_RESULT" | jq -e '.data.data' &> /dev/null; then
        pass "Secret read successful"
        echo "  Secret keys: $(echo "$SECRET_RESULT" | jq -r '.data.data | keys | join(", ")')"
    else
        warn "Secret read failed (secret may not exist yet)"
        echo "  Result: $SECRET_RESULT"
    fi
else
    warn "Skipping - no token from previous test"
fi
echo ""

# Test 8: Vault Agent Injector
echo "============================================"
echo "Test 8: Vault Agent Injector verification"
echo "============================================"
echo "Checking for injected secrets in test-pod-injector..."

# Check if the vault-agent-init container ran
INIT_STATUS=$(kubectl get pod test-pod-injector -n vault-test -o jsonpath='{.status.initContainerStatuses[?(@.name=="vault-agent-init")].state}' 2>/dev/null)

if [ -n "$INIT_STATUS" ]; then
    echo "  Init container state: $INIT_STATUS"

    # Try to read the injected secret
    INJECTED_SECRET=$(kubectl exec test-pod-injector -n vault-test -c app -- \
        cat /vault/secrets/config.txt 2>&1) || true

    if [ -n "$INJECTED_SECRET" ] && [ "$INJECTED_SECRET" != "cat: /vault/secrets/config.txt: No such file or directory" ]; then
        pass "Secrets injected by Vault Agent"
        echo "  Injected content preview: ${INJECTED_SECRET:0:100}..."
    else
        warn "Secrets not yet injected (init container may still be running)"
        echo "  Check pod events: kubectl describe pod test-pod-injector -n vault-test"
    fi
else
    warn "Vault Agent init container not found"
    echo "  The injector may not have modified this pod"
fi
echo ""

# Test 9: Wrong role rejection
echo "============================================"
echo "Test 9: Wrong role rejection"
echo "============================================"
echo "Attempting authentication with non-existent role..."

WRONG_ROLE_RESULT=$(kubectl exec test-pod-manual -n vault-test -- \
    vault write auth/kubernetes/login \
    role=nonexistent-role \
    jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token 2>&1) || true

if echo "$WRONG_ROLE_RESULT" | grep -qi "error\|permission denied\|role.*not found"; then
    pass "Wrong role correctly rejected"
else
    fail "Wrong role was NOT rejected (unexpected)"
fi
echo ""

# Summary
echo "============================================"
echo "  Test Summary"
echo "============================================"
echo ""
echo -e "  ${GREEN}Passed${NC}: $PASS_COUNT"
echo -e "  ${RED}Failed${NC}: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${YELLOW}Some tests failed. Check the output above for details.${NC}"
    exit 1
fi
