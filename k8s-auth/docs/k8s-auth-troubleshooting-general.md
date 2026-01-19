# Vault Kubernetes Auth - General Troubleshooting Guide

This guide covers common issues with Vault's Kubernetes authentication method in **any environment** (production, managed K8s, self-hosted). For lab-specific issues (Minikube + ngrok), see [troubleshooting.md](troubleshooting.md).

---

## Table of Contents

1. [Quick Diagnostic Checklist](#quick-diagnostic-checklist)
2. [Authentication Flow Overview](#authentication-flow-overview)
3. [Error Reference](#error-reference)
   - [Permission Denied](#1-permission-denied)
   - [Service Account Not Authorized](#2-service-account-not-authorized)
   - [Invalid JWT](#3-invalid-jwt)
   - [Token Issuer Mismatch](#4-token-issuer-mismatch)
   - [Audience Mismatch](#5-audience-mismatch)
   - [Certificate Errors](#6-certificate-errors)
   - [Connection Errors](#7-connection-errors)
   - [TokenReview Failed](#8-tokenreview-failed)
4. [Managed Kubernetes Specifics](#managed-kubernetes-specifics)
5. [Common Misconfigurations](#common-misconfigurations)
6. [Diagnostic Commands](#diagnostic-commands)

---

## Quick Diagnostic Checklist

When auth fails, verify these in order:

```
[ ] 1. Vault can reach kubernetes_host URL
[ ] 2. Token reviewer JWT is valid (not expired)
[ ] 3. vault-auth ServiceAccount has system:auth-delegator ClusterRoleBinding
[ ] 4. Pod's ServiceAccount matches role's bound_service_account_names
[ ] 5. Pod's namespace matches role's bound_service_account_namespaces
[ ] 6. JWT issuer matches Vault's expected issuer (or disable_iss_validation=true)
[ ] 7. CA certificate is valid and not expired (if using kubernetes_ca_cert)
[ ] 8. Role has policies attached
```

---

## Authentication Flow Overview

Understanding the flow helps pinpoint where failures occur:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VAULT K8S AUTH FLOW                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  STEP 1: Pod reads its ServiceAccount JWT                                   │
│  ────────────────────────────────────────                                   │
│  Location: /var/run/secrets/kubernetes.io/serviceaccount/token              │
│  Failure: File missing, wrong permissions, token expired                    │
│                                                                             │
│                              │                                              │
│                              ▼                                              │
│                                                                             │
│  STEP 2: Pod sends JWT to Vault                                             │
│  ───────────────────────────────                                            │
│  Request: vault write auth/kubernetes/login role=X jwt=<token>              │
│  Failure: Can't reach Vault, wrong auth path, role doesn't exist            │
│                                                                             │
│                              │                                              │
│                              ▼                                              │
│                                                                             │
│  STEP 3: Vault calls Kubernetes TokenReview API                             │
│  ──────────────────────────────────────────────                             │
│  Uses: token_reviewer_jwt to authenticate to K8s API                        │
│  Sends: Pod's JWT for validation                                            │
│  Failure: Can't reach K8s API, reviewer JWT invalid, RBAC denied            │
│                                                                             │
│                              │                                              │
│                              ▼                                              │
│                                                                             │
│  STEP 4: Kubernetes validates the JWT                                       │
│  ─────────────────────────────────────                                      │
│  Checks: Signature, expiry, issuer, audience                                │
│  Returns: ServiceAccount name, namespace, UID                               │
│  Failure: Invalid/expired token, wrong issuer, audience mismatch            │
│                                                                             │
│                              │                                              │
│                              ▼                                              │
│                                                                             │
│  STEP 5: Vault checks role bindings                                         │
│  ───────────────────────────────────                                        │
│  Verifies: SA name in bound_service_account_names                           │
│  Verifies: Namespace in bound_service_account_namespaces                    │
│  Failure: SA or namespace not in allowed list                               │
│                                                                             │
│                              │                                              │
│                              ▼                                              │
│                                                                             │
│  STEP 6: Vault issues token with policies                                   │
│  ─────────────────────────────────────────                                  │
│  Attaches: Policies from the role                                           │
│  Returns: Vault token to pod                                                │
│  Failure: No policies = can't access secrets                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Error Reference

### 1. Permission Denied

**Symptom:**
```
Error making API request.
Code: 403. Errors:
* permission denied
```

**Possible Causes (in order of likelihood):**

| Cause | How to Verify | Solution |
|-------|---------------|----------|
| ServiceAccount name mismatch | Compare pod SA vs role | Update role's `bound_service_account_names` |
| Namespace mismatch | Compare pod namespace vs role | Update role's `bound_service_account_namespaces` |
| Role doesn't exist | `vault list auth/kubernetes/role` | Create the role |
| Using wrong role name | Check login command | Use correct role name |

**Debug Commands:**
```bash
# What does the role expect?
vault read auth/kubernetes/role/<role-name>

# What is the pod's ServiceAccount?
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'

# What namespace is the pod in?
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.namespace}'
```

**Fix Example:**
```bash
# Update role to allow the correct SA and namespace
vault write auth/kubernetes/role/my-role \
    bound_service_account_names=my-app-sa \
    bound_service_account_namespaces=production \
    policies=my-policy \
    ttl=1h
```

---

### 2. Service Account Not Authorized

**Symptom:**
```
* service account name not authorized
```

**Cause:** The ServiceAccount name from the JWT doesn't match any name in `bound_service_account_names`.

**Debug:**
```bash
# Decode the JWT to see what SA it claims
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq '.["kubernetes.io/serviceaccount/service-account.name"]'

# Compare with role config
vault read -format=json auth/kubernetes/role/<role> | \
  jq '.data.bound_service_account_names'
```

**Common Mistakes:**
- Typo in ServiceAccount name
- Using `default` SA but role expects named SA
- Wildcard `*` not set when intending to allow all SAs

**Fix:**
```bash
# Allow specific SA
vault write auth/kubernetes/role/my-role \
    bound_service_account_names=correct-sa-name \
    ...

# Or allow all SAs in a namespace (use cautiously)
vault write auth/kubernetes/role/my-role \
    bound_service_account_names="*" \
    bound_service_account_namespaces=my-namespace \
    ...
```

---

### 3. Invalid JWT

**Symptom:**
```
* error validating token: invalid JWT
```
or
```
* could not validate JWT: JWT is not valid
```

**Possible Causes:**

| Cause | How to Verify | Solution |
|-------|---------------|----------|
| Token expired | Decode JWT, check `exp` claim | Get fresh token (restart pod) |
| Malformed token | Try decoding manually | Check token file isn't corrupted |
| Wrong token used | Verify source of token | Use token from pod's SA mount |
| Vault can't reach K8s API | Check connectivity | Fix network/firewall |

**Debug:**
```bash
# Check token expiry
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq '.exp | todate'

# Check if token is well-formed (should have 3 parts)
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | \
  tr '.' '\n' | wc -l
# Should output: 3
```

---

### 4. Token Issuer Mismatch

**Symptom:**
```
* claim "iss" is invalid
* iss claim does not match expected issuer
```

**Cause:** The JWT's `iss` (issuer) claim doesn't match what Vault expects.

**Why This Happens:**
- Kubernetes 1.21+ uses OIDC issuer URLs
- Managed K8s (EKS/GKE/AKS) have cloud-specific issuers
- Self-hosted clusters may have custom issuers

**Debug:**
```bash
# Check what issuer the JWT has
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq '.iss'

# Check what Vault expects
vault read auth/kubernetes/config
```

**Solutions:**

Option 1: Disable issuer validation (simpler, slightly less secure)
```bash
vault write auth/kubernetes/config \
    kubernetes_host="https://<k8s-api>" \
    disable_iss_validation=true \
    ...
```

Option 2: Set the correct issuer (more secure)
```bash
# First, find the actual issuer
ISSUER=$(kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.iss')

vault write auth/kubernetes/config \
    kubernetes_host="https://<k8s-api>" \
    issuer="$ISSUER" \
    ...
```

---

### 5. Audience Mismatch

**Symptom:**
```
* aud claim does not match expected audience
* invalid audience claim
```

**Why This Happens:**
- Kubernetes 1.21+ projects tokens with specific audiences
- Default audience is often the API server, not "vault"
- Bound Service Account Tokens have explicit audiences

**Debug:**
```bash
# Check token's audience
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq '.aud'
```

**Solutions:**

Option 1: Use legacy tokens (if available)
```yaml
# Create a static token secret (pre-1.24 style)
apiVersion: v1
kind: Secret
metadata:
  name: my-sa-token
  annotations:
    kubernetes.io/service-account.name: my-sa
type: kubernetes.io/service-account-token
```

Option 2: Project a token with correct audience
```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    volumeMounts:
    - name: vault-token
      mountPath: /var/run/secrets/vault
  volumes:
  - name: vault-token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600
          audience: vault  # Match Vault's expected audience
```

Option 3: Configure Vault to accept the audience
```bash
vault write auth/kubernetes/config \
    kubernetes_host="https://<k8s-api>" \
    audience="https://kubernetes.default.svc"  # Match token's aud
    ...
```

---

### 6. Certificate Errors

**Symptom:**
```
* x509: certificate signed by unknown authority
* x509: certificate has expired
* x509: certificate is valid for X, not Y
```

**For detailed certificate troubleshooting, run:**
```bash
./scripts/06-inspect-certificates.sh
```

**Quick Fixes:**

| Error | Cause | Solution |
|-------|-------|----------|
| signed by unknown authority | Missing CA cert | Add `kubernetes_ca_cert` to config |
| certificate has expired | CA or TLS cert expired | Rotate certificates |
| valid for X, not Y | Hostname mismatch | Use hostname in cert's SANs |

**Get the CA certificate:**
```bash
# From kubectl config
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d

# From a running pod
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

**Configure Vault with CA cert:**
```bash
K8S_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

vault write auth/kubernetes/config \
    kubernetes_host="https://<k8s-api>" \
    kubernetes_ca_cert="$K8S_CA" \
    ...
```

---

### 7. Connection Errors

**Symptom:**
```
* connection refused
* dial tcp: lookup <host>: no such host
* context deadline exceeded
* EOF
```

**Possible Causes:**

| Error | Cause | Solution |
|-------|-------|----------|
| connection refused | K8s API not reachable | Check firewall, network |
| no such host | DNS resolution failed | Check DNS, use IP instead |
| context deadline exceeded | Network timeout | Check routing, latency |
| EOF | TLS handshake failed | Check certificates |

**Debug:**
```bash
# Test from Vault server (if you have access)
curl -k https://<kubernetes_host>/healthz

# Check what Vault has configured
vault read auth/kubernetes/config

# Test DNS resolution
nslookup <kubernetes-api-hostname>
```

---

### 8. TokenReview Failed

**Symptom:**
```
* lookup failed
* serviceaccount [...] not found
* error calling TokenReview API
```

**Cause:** Vault's `token_reviewer_jwt` can't successfully call the TokenReview API.

**Common Causes:**

| Cause | Solution |
|-------|----------|
| vault-auth SA missing | Create the ServiceAccount |
| Missing ClusterRoleBinding | Bind `system:auth-delegator` |
| token_reviewer_jwt expired | Refresh the token |
| Wrong namespace for SA | Use `kube-system` namespace |

**Required RBAC Setup:**
```yaml
# ServiceAccount for Vault to use
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: kube-system
---
# Bind auth-delegator role (allows TokenReview)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: kube-system
```

**Verify RBAC:**
```bash
# Check ServiceAccount exists
kubectl get sa vault-auth -n kube-system

# Check ClusterRoleBinding exists
kubectl get clusterrolebinding | grep vault

# Describe to see details
kubectl describe clusterrolebinding vault-auth-tokenreview
```

**Refresh token_reviewer_jwt:**
```bash
# Get fresh token
TOKEN=$(kubectl get secret vault-auth-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)

# Update Vault config
vault write auth/kubernetes/config \
    kubernetes_host="$KUBERNETES_HOST" \
    token_reviewer_jwt="$TOKEN" \
    ...
```

---

## Managed Kubernetes Specifics

### Amazon EKS

**OIDC Issuer:**
```bash
# Get EKS OIDC issuer
aws eks describe-cluster --name <cluster> --query 'cluster.identity.oidc.issuer' --output text
# Example: https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE
```

**EKS Config:**
```bash
vault write auth/kubernetes/config \
    kubernetes_host="https://<eks-api-endpoint>" \
    issuer="https://oidc.eks.<region>.amazonaws.com/id/<id>" \
    # OR disable_iss_validation=true
```

### Google GKE

**OIDC Issuer:**
```bash
# Usually: https://container.googleapis.com/v1/projects/<project>/locations/<zone>/clusters/<cluster>
# Or for Workload Identity: https://gkehub.googleapis.com/projects/<project>/locations/global/memberships/<membership>
```

**GKE Note:** GKE Autopilot and Workload Identity may require additional configuration.

### Azure AKS

**OIDC Issuer:**
```bash
az aks show --resource-group <rg> --name <cluster> --query 'oidcIssuerProfile.issuerUrl' -o tsv
# Example: https://eastus.oic.prod-aks.azure.com/<tenant-id>/<id>/
```

---

## Common Misconfigurations

### 1. Using Pod's JWT as token_reviewer_jwt

**Wrong:** Using an application pod's short-lived token for Vault's reviewer JWT.

**Right:** Create a dedicated `vault-auth` ServiceAccount with a long-lived token.

### 2. Forgetting to bind service account names

**Wrong:**
```bash
vault write auth/kubernetes/role/my-role \
    policies=my-policy \
    ttl=1h
# Missing bound_service_account_names and bound_service_account_namespaces!
```

**Right:**
```bash
vault write auth/kubernetes/role/my-role \
    bound_service_account_names=my-sa \
    bound_service_account_namespaces=my-namespace \
    policies=my-policy \
    ttl=1h
```

### 3. Wrong auth path

**Wrong:**
```bash
vault write auth/k8s/login ...        # Wrong path
vault write auth/kube/login ...       # Wrong path
```

**Right:**
```bash
vault write auth/kubernetes/login ... # Default path
# Or if mounted at custom path:
vault write auth/<custom-path>/login ...
```

### 4. Role with no policies

Auth succeeds, but can't access any secrets:
```bash
# Check role has policies
vault read auth/kubernetes/role/<role> | grep policies
# If empty, add policies:
vault write auth/kubernetes/role/<role> policies=my-policy,...
```

---

## Diagnostic Commands

### Complete Health Check Script

```bash
#!/bin/bash
echo "=== Vault K8s Auth Diagnostic ==="

echo -e "\n[1] Vault Status"
vault status

echo -e "\n[2] K8s Auth Enabled?"
vault auth list | grep kubernetes

echo -e "\n[3] K8s Auth Config"
vault read auth/kubernetes/config

echo -e "\n[4] Available Roles"
vault list auth/kubernetes/role

echo -e "\n[5] Role Details"
for role in $(vault list -format=json auth/kubernetes/role 2>/dev/null | jq -r '.[]'); do
    echo "--- Role: $role ---"
    vault read auth/kubernetes/role/$role
done

echo -e "\n[6] Test TokenReview (from a pod)"
echo "Run inside pod:"
echo 'vault write auth/kubernetes/login role=<role> jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)'
```

### Decode JWT Token

```bash
# Full decode
decode_jwt() {
    echo "=== JWT Header ==="
    echo "$1" | cut -d. -f1 | base64 -d 2>/dev/null | jq .
    echo "=== JWT Payload ==="
    echo "$1" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
}

# Usage from pod:
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
decode_jwt "$TOKEN"
```

### Test Login Manually

```bash
# From inside a pod
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Test with curl
curl -s --request POST \
    --data "{\"jwt\": \"$JWT\", \"role\": \"my-role\"}" \
    $VAULT_ADDR/v1/auth/kubernetes/login | jq .

# Test with vault CLI
vault write auth/kubernetes/login role=my-role jwt=$JWT
```

---

## See Also

- [Vault K8s Auth Docs](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [Vault K8s Auth API](https://developer.hashicorp.com/vault/api-docs/auth/kubernetes)
- [Certificate Inspection Script](../scripts/06-inspect-certificates.sh) - For certificate troubleshooting
- [Lab-Specific Troubleshooting](troubleshooting.md) - For Minikube + ngrok issues
