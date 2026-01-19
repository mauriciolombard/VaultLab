# Vault Kubernetes Authentication Flow

A comprehensive guide to understanding and troubleshooting Vault's Kubernetes authentication method. This document works for any Kubernetes environment (self-hosted, EKS, GKE, AKS, Minikube).

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [The Authentication Flow](#the-authentication-flow)
3. [Deep Dives](#deep-dives)
4. [Environment-Specific Considerations](#environment-specific-considerations)
5. [Troubleshooting by Error Message](#troubleshooting-by-error-message)
6. [Configuration Reference](#configuration-reference)

---

## Quick Reference

### The Flow at a Glance

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                 VAULT KUBERNETES AUTHENTICATION FLOW                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────┐      ┌─────────┐      ┌─────────┐      ┌─────────┐            │
│  │   POD   │ ──── │  VAULT  │ ──── │   K8S   │ ──── │  VAULT  │            │
│  │         │  1   │         │  2   │   API   │  3   │         │            │
│  │ Read    │ ───► │ Login   │ ───► │ Token   │ ───► │ Check   │            │
│  │ JWT     │      │ Request │      │ Review  │      │ Role    │            │
│  └─────────┘      └─────────┘      └─────────┘      └────┬────┘            │
│       │                                                   │                 │
│       │                                                   │ 4               │
│       │              ┌─────────┐      ┌─────────┐         │                 │
│       │              │   POD   │ ◄─── │  VAULT  │ ◄───────┘                 │
│       │              │         │  6   │         │  5                        │
│       └──────────────│ Access  │ ◄─── │ Issue   │                           │
│         Uses token   │ Secrets │      │ Token   │                           │
│                      └─────────┘      └─────────┘                           │
│                                                                             │
│  Step 1: Pod reads JWT from /var/run/secrets/.../token                      │
│  Step 2: Pod sends JWT to Vault's /auth/kubernetes/login                    │
│  Step 3: Vault calls K8s TokenReview API to validate JWT                    │
│  Step 4: Vault checks if SA/namespace match role bindings                   │
│  Step 5: Vault issues client token with policies                            │
│  Step 6: Pod uses Vault token to access secrets                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Which Step Failed? Quick Diagnostic

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        QUICK DIAGNOSTIC TREE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Can pod read its JWT token?                                                │
│  $ kubectl exec <pod> -- cat /var/run/secrets/.../token | head -c50        │
│  ├── NO  → STEP 1 FAILED: Token not mounted                                │
│  └── YES ↓                                                                  │
│                                                                             │
│  Can pod reach Vault?                                                       │
│  $ kubectl exec <pod> -- wget -qO- $VAULT_ADDR/v1/sys/health               │
│  ├── NO  → NETWORK ISSUE: Check Vault address, firewall                    │
│  └── YES ↓                                                                  │
│                                                                             │
│  Does login return an error?                                                │
│  $ vault write auth/kubernetes/login role=X jwt=@token                     │
│  │                                                                          │
│  ├── "permission denied"          → STEP 4: Role binding mismatch          │
│  ├── "service account not found"  → STEP 4: SA name not in role            │
│  ├── "namespace not authorized"   → STEP 4: Namespace not in role          │
│  ├── "could not validate JWT"     → STEP 3: TokenReview failed             │
│  ├── "connection refused"         → STEP 3: Vault can't reach K8s API      │
│  ├── "iss claim invalid"          → STEP 3: Issuer mismatch                │
│  └── Success but can't read secrets → STEP 6: Policy issue                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Command Cheat Sheet by Step

```bash
# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: Check JWT Token
# ══════════════════════════════════════════════════════════════════════════════
# Does token file exist?
kubectl exec <POD> -n <NS> -- ls -la /var/run/secrets/kubernetes.io/serviceaccount/

# Read token (first 50 chars)
kubectl exec <POD> -n <NS> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | head -c 50

# Decode JWT payload
kubectl exec <POD> -n <NS> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq .

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: Check Vault Connectivity
# ══════════════════════════════════════════════════════════════════════════════
# Can pod reach Vault?
kubectl exec <POD> -n <NS> -- wget -qO- ${VAULT_ADDR}/v1/sys/health

# Is kubernetes auth enabled?
vault auth list | grep kubernetes

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: Check TokenReview (Vault → K8s API)
# ══════════════════════════════════════════════════════════════════════════════
# What's the configured kubernetes_host?
vault read auth/kubernetes/config

# Test K8s API connectivity (from Vault's perspective)
# Run this from Vault server or test with curl
curl -sk https://<kubernetes_host>/healthz

# Check token_reviewer_jwt is valid
vault read -format=json auth/kubernetes/config | jq -r '.data.token_reviewer_jwt' | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq .exp

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4: Check Role Bindings
# ══════════════════════════════════════════════════════════════════════════════
# List all roles
vault list auth/kubernetes/role

# Read specific role
vault read auth/kubernetes/role/<ROLE>

# Check bound SA names and namespaces
vault read -format=json auth/kubernetes/role/<ROLE> | \
  jq '{bound_service_account_names, bound_service_account_namespaces, policies}'

# What SA is the pod using?
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.serviceAccountName}'

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 & 6: Test Full Authentication
# ══════════════════════════════════════════════════════════════════════════════
# Full login test from pod
kubectl exec <POD> -n <NS> -- \
  vault write auth/kubernetes/login \
    role=<ROLE> \
    jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

# Check resulting token capabilities
vault token capabilities <TOKEN> secret/data/myapp/config
```

---

## The Authentication Flow

### Step 1: Pod Reads Its JWT Token

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1: POD READS JWT TOKEN                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHAT HAPPENS                                                               │
│  ─────────────                                                              │
│  Kubernetes automatically mounts a ServiceAccount token into every pod.    │
│  The pod reads this JWT to prove its identity to Vault.                     │
│                                                                             │
│  Location: /var/run/secrets/kubernetes.io/serviceaccount/token              │
│                                                                             │
│  TOKEN STRUCTURE (decoded)                                                  │
│  ─────────────────────────                                                  │
│  {                                                                          │
│    "iss": "https://kubernetes.default.svc",     ◄── Issuer (varies!)       │
│    "sub": "system:serviceaccount:NS:SA-NAME",   ◄── Subject (identity)     │
│    "aud": ["https://kubernetes.default.svc"],   ◄── Audience               │
│    "exp": 1699999999,                           ◄── Expiration             │
│    "iat": 1699990000,                           ◄── Issued at              │
│    "kubernetes.io/serviceaccount/namespace": "vault-test",                  │
│    "kubernetes.io/serviceaccount/service-account.name": "vault-sa"         │
│  }                                                                          │
│                                                                             │
│  KEY PLAYERS                                                                │
│  ───────────                                                                │
│  • ServiceAccount: The identity assigned to the pod                         │
│  • Kubernetes: Mounts the token automatically                               │
│  • Token Projection: Creates short-lived tokens (K8s 1.21+)                 │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WHAT CAN GO WRONG                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Problem                      │ Cause                    │ Solution         │
│  ────────────────────────────│─────────────────────────│─────────────────  │
│  Token file missing           │ SA doesn't exist         │ Create SA        │
│  Token file empty             │ Token projection failed  │ Check K8s logs   │
│  Token expired                │ Pod running too long     │ Restart pod      │
│  Wrong SA mounted             │ Pod spec incorrect       │ Check podspec    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ DEBUG COMMANDS                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Check token exists                                                       │
│  kubectl exec <POD> -n <NS> -- \                                           │
│    ls -la /var/run/secrets/kubernetes.io/serviceaccount/                   │
│                                                                             │
│  # Expected output:                                                         │
│  # -rw-r--r-- 1 root root  xxx ca.crt                                      │
│  # -rw-r--r-- 1 root root  xxx namespace                                   │
│  # -rw-r--r-- 1 root root  xxx token        ◄── This must exist            │
│                                                                             │
│  # Decode and check token                                                   │
│  kubectl exec <POD> -n <NS> -- \                                           │
│    cat /var/run/secrets/kubernetes.io/serviceaccount/token | \             │
│    cut -d. -f2 | base64 -d 2>/dev/null | jq .                              │
│                                                                             │
│  # Check expiry (is it in the future?)                                      │
│  kubectl exec <POD> -n <NS> -- \                                           │
│    cat /var/run/secrets/kubernetes.io/serviceaccount/token | \             │
│    cut -d. -f2 | base64 -d 2>/dev/null | jq '.exp | todate'               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 2: Pod Sends Login Request to Vault

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 2: POD SENDS LOGIN REQUEST TO VAULT                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHAT HAPPENS                                                               │
│  ─────────────                                                              │
│  The pod sends its JWT to Vault's kubernetes auth endpoint.                 │
│  Vault will validate this token in the next step.                           │
│                                                                             │
│  REQUEST                                                                    │
│  ───────                                                                    │
│  POST $VAULT_ADDR/v1/auth/kubernetes/login                                  │
│  {                                                                          │
│    "role": "my-role",           ◄── Role name (must exist in Vault)        │
│    "jwt": "eyJhbGciOiJ..."      ◄── ServiceAccount token from Step 1       │
│  }                                                                          │
│                                                                             │
│  CLI EQUIVALENT                                                             │
│  ──────────────                                                             │
│  vault write auth/kubernetes/login \                                        │
│    role=my-role \                                                           │
│    jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token                │
│                                                                             │
│  KEY PLAYERS                                                                │
│  ───────────                                                                │
│  • Pod: Sends the request                                                   │
│  • Vault: Receives and will validate                                        │
│  • Network: Must allow pod → Vault communication                            │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WHAT CAN GO WRONG                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Problem                      │ Cause                    │ Solution         │
│  ────────────────────────────│─────────────────────────│─────────────────  │
│  Connection refused           │ Wrong VAULT_ADDR         │ Check address    │
│  Connection timeout           │ Firewall/NetworkPolicy   │ Check network    │
│  TLS error                    │ Certificate mismatch     │ Check TLS config │
│  "no handler for route"       │ K8s auth not enabled     │ Enable auth      │
│  "role not found"             │ Role doesn't exist       │ Create role      │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ SUCCESS LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  At this point, Vault has RECEIVED the request but NOT yet validated it.    │
│  Validation happens in Step 3. Success here means the request was sent.     │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ FAILURE LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Connection refused (wrong address or Vault down)                         │
│  Error making API request: dial tcp 10.0.0.1:8200: connect: connection refused
│                                                                             │
│  # TLS error (certificate issue)                                            │
│  Error making API request: tls: failed to verify certificate                │
│                                                                             │
│  # Auth method not enabled                                                  │
│  Error writing data: 404 no handler for route "auth/kubernetes/login"       │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ DEBUG COMMANDS                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Check Vault is reachable from pod                                        │
│  kubectl exec <POD> -n <NS> -- wget -qO- $VAULT_ADDR/v1/sys/health         │
│                                                                             │
│  # Expected: {"initialized":true,"sealed":false,...}                        │
│                                                                             │
│  # Check kubernetes auth is enabled                                         │
│  vault auth list | grep kubernetes                                          │
│                                                                             │
│  # Expected: kubernetes/    kubernetes    ...                               │
│                                                                             │
│  # Check role exists                                                        │
│  vault list auth/kubernetes/role                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 3: Vault Validates JWT via TokenReview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 3: VAULT VALIDATES JWT VIA TOKENREVIEW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHAT HAPPENS                                                               │
│  ─────────────                                                              │
│  Vault does NOT validate the JWT itself. Instead, it asks Kubernetes        │
│  to validate it using the TokenReview API. This is the critical step        │
│  where most authentication failures occur.                                  │
│                                                                             │
│  FLOW                                                                       │
│  ────                                                                       │
│                                                                             │
│  Vault                          Kubernetes API                              │
│    │                                  │                                     │
│    │  POST /apis/authentication.k8s.io/v1/tokenreviews                      │
│    │  Authorization: Bearer <token_reviewer_jwt>                            │
│    │  {                               │                                     │
│    │    "spec": {                     │                                     │
│    │      "token": "<pod_jwt>"        │                                     │
│    │    }                             │                                     │
│    │  }                               │                                     │
│    │ ──────────────────────────────►  │                                     │
│    │                                  │                                     │
│    │   {                              │                                     │
│    │     "status": {                  │                                     │
│    │       "authenticated": true,     │                                     │
│    │       "user": {                  │                                     │
│    │         "username": "system:serviceaccount:NS:SA"                      │
│    │       }                          │                                     │
│    │     }                            │                                     │
│    │   }                              │                                     │
│    │ ◄──────────────────────────────  │                                     │
│    │                                  │                                     │
│                                                                             │
│  KEY CONFIGURATION                                                          │
│  ─────────────────                                                          │
│  • kubernetes_host: URL Vault uses to reach K8s API                         │
│  • token_reviewer_jwt: Vault's credential for calling TokenReview           │
│  • kubernetes_ca_cert: CA cert to verify K8s API TLS (optional)             │
│                                                                             │
│  KEY PLAYERS                                                                │
│  ───────────                                                                │
│  • Vault: Calls the TokenReview API                                         │
│  • vault-auth ServiceAccount: Provides token_reviewer_jwt                   │
│  • system:auth-delegator ClusterRole: Grants TokenReview permission         │
│  • Kubernetes API: Validates the token                                      │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WHAT CAN GO WRONG                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Problem                      │ Cause                    │ Solution         │
│  ────────────────────────────│─────────────────────────│─────────────────  │
│  "connection refused"         │ Wrong kubernetes_host    │ Fix URL          │
│  "no such host"               │ DNS resolution failed    │ Check DNS/URL    │
│  "certificate error"          │ TLS/CA mismatch          │ Fix CA cert      │
│  "unauthorized"               │ token_reviewer_jwt bad   │ Refresh JWT      │
│  "forbidden"                  │ Missing RBAC binding     │ Add auth-delegator
│  "iss claim invalid"          │ Issuer mismatch          │ Set issuer or    │
│                               │                          │ disable_iss_validation
│  "aud claim invalid"          │ Audience mismatch        │ Configure audience │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ SUCCESS LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  TokenReview returns:                                                       │
│  {                                                                          │
│    "status": {                                                              │
│      "authenticated": true,                 ◄── Must be true               │
│      "user": {                                                              │
│        "username": "system:serviceaccount:vault-test:vault-sa",            │
│        "uid": "abc123...",                                                  │
│        "groups": ["system:serviceaccounts", "system:authenticated"]        │
│      }                                                                      │
│    }                                                                        │
│  }                                                                          │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ FAILURE LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Vault can't reach K8s API                                                │
│  error="Put \"https://kubernetes:443/apis/authentication.k8s.io/v1/tokenreviews\":
│         dial tcp: lookup kubernetes: no such host"                          │
│                                                                             │
│  # token_reviewer_jwt doesn't have permission                               │
│  error="tokenreviews.authentication.k8s.io is forbidden:                    │
│         User \"system:serviceaccount:kube-system:vault-auth\" cannot create │
│         resource \"tokenreviews\""                                          │
│                                                                             │
│  # Issuer mismatch                                                          │
│  error="claim \"iss\" is invalid"                                          │
│                                                                             │
│  # Token expired or invalid                                                 │
│  error="token is expired"                                                   │
│  error="token not valid"                                                    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ DEBUG COMMANDS                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Check Vault's kubernetes auth config                                     │
│  vault read auth/kubernetes/config                                          │
│                                                                             │
│  # Verify kubernetes_host is reachable                                      │
│  KUBERNETES_HOST=$(vault read -format=json auth/kubernetes/config | \       │
│    jq -r '.data.kubernetes_host')                                          │
│  curl -sk $KUBERNETES_HOST/healthz                                         │
│                                                                             │
│  # Check token_reviewer_jwt isn't expired                                   │
│  vault read -format=json auth/kubernetes/config | \                         │
│    jq -r '.data.token_reviewer_jwt' | \                                    │
│    cut -d. -f2 | base64 -d 2>/dev/null | jq '.exp | todate'               │
│                                                                             │
│  # Verify vault-auth SA has correct ClusterRoleBinding                      │
│  kubectl get clusterrolebinding | grep vault                                │
│  kubectl describe clusterrolebinding vault-auth-tokenreview                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 4: Vault Checks Role Bindings

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 4: VAULT CHECKS ROLE BINDINGS                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHAT HAPPENS                                                               │
│  ─────────────                                                              │
│  After TokenReview confirms the JWT is valid, Vault extracts the            │
│  ServiceAccount name and namespace, then checks if they're allowed          │
│  by the specified role.                                                     │
│                                                                             │
│  VALIDATION LOGIC                                                           │
│  ────────────────                                                           │
│                                                                             │
│  From TokenReview:                  From Role Config:                       │
│  ┌──────────────────────────┐      ┌──────────────────────────────────┐    │
│  │ namespace: "vault-test"  │  ?=  │ bound_service_account_namespaces │    │
│  │ sa_name:   "vault-sa"    │  ?=  │ bound_service_account_names      │    │
│  └──────────────────────────┘      └──────────────────────────────────┘    │
│                                                                             │
│  BOTH must match for authentication to succeed.                             │
│                                                                             │
│  ROLE CONFIGURATION EXAMPLE                                                 │
│  ──────────────────────────                                                 │
│  vault write auth/kubernetes/role/my-role \                                 │
│    bound_service_account_names="app-sa,worker-sa" \     ◄── Allowed SAs    │
│    bound_service_account_namespaces="production,staging" \ ◄── Allowed NS  │
│    policies="app-policy" \                              ◄── Attached policies
│    ttl=1h                                               ◄── Token lifetime │
│                                                                             │
│  WILDCARD SUPPORT                                                           │
│  ────────────────                                                           │
│  • "*" = Allow any ServiceAccount name                                      │
│  • "*" = Allow any namespace                                                │
│  ⚠️  Use wildcards carefully - they reduce security                         │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WHAT CAN GO WRONG                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Problem                      │ Cause                    │ Solution         │
│  ────────────────────────────│─────────────────────────│─────────────────  │
│  "permission denied"          │ SA or NS not in role     │ Update role      │
│  "service account not auth"   │ SA name doesn't match    │ Check SA name    │
│  "namespace not authorized"   │ NS doesn't match         │ Check namespace  │
│  Typo in role binding         │ "vault-sa" vs "vault_sa" │ Check exact name │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ SUCCESS LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  No output at this step - if it passes, Vault proceeds to Step 5.           │
│  The validation is internal to Vault.                                       │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ FAILURE LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # ServiceAccount name not in bound list                                    │
│  Error writing data: permission denied                                      │
│                                                                             │
│  # More specific error (sometimes shown)                                    │
│  Error writing data: service account name not authorized                    │
│                                                                             │
│  # Namespace not in bound list                                              │
│  Error writing data: namespace not authorized                               │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ DEBUG COMMANDS                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Read the role configuration                                              │
│  vault read auth/kubernetes/role/<ROLE>                                     │
│                                                                             │
│  # Extract just the bindings                                                │
│  vault read -format=json auth/kubernetes/role/<ROLE> | \                    │
│    jq '{bound_service_account_names, bound_service_account_namespaces}'    │
│                                                                             │
│  # Check what SA the pod is using                                           │
│  kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.serviceAccountName}'    │
│                                                                             │
│  # Check pod's namespace                                                    │
│  kubectl get pod <POD> -o jsonpath='{.metadata.namespace}'                 │
│                                                                             │
│  # Compare: Does SA match? Does namespace match?                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 5: Vault Issues Token

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 5: VAULT ISSUES TOKEN                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHAT HAPPENS                                                               │
│  ─────────────                                                              │
│  All checks passed. Vault creates a client token with:                      │
│  • Policies from the role configuration                                     │
│  • TTL from the role configuration                                          │
│  • Metadata about the authenticated identity                                │
│                                                                             │
│  RESPONSE STRUCTURE                                                         │
│  ──────────────────                                                         │
│  {                                                                          │
│    "auth": {                                                                │
│      "client_token": "hvs.CAESI...",      ◄── The Vault token              │
│      "accessor": "abc123...",              ◄── Token accessor              │
│      "policies": ["default", "app-policy"],                                 │
│      "token_policies": ["default", "app-policy"],                          │
│      "metadata": {                                                          │
│        "role": "my-role",                  ◄── Which role was used         │
│        "service_account_name": "vault-sa", ◄── Authenticated identity     │
│        "service_account_namespace": "vault-test"                           │
│      },                                                                     │
│      "lease_duration": 3600,               ◄── TTL in seconds              │
│      "renewable": true                     ◄── Can be renewed              │
│    }                                                                        │
│  }                                                                          │
│                                                                             │
│  TOKEN PROPERTIES                                                           │
│  ────────────────                                                           │
│  • TTL: How long until token expires (from role's token_ttl)                │
│  • Max TTL: Maximum renewable lifetime (from role's token_max_ttl)          │
│  • Policies: What the token can access (from role's policies)               │
│  • Renewable: Can the token be renewed before expiry                        │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WHAT CAN GO WRONG                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  At this step, authentication has succeeded. Issues here are rare:          │
│                                                                             │
│  Problem                      │ Cause                    │ Solution         │
│  ────────────────────────────│─────────────────────────│─────────────────  │
│  No policies attached         │ Role has no policies     │ Add policies     │
│  Very short TTL               │ Role TTL too low         │ Increase TTL     │
│  Token immediately expires    │ Clock skew               │ Sync clocks      │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ SUCCESS LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Key          Value                                                         │
│  ---          -----                                                         │
│  token        hvs.CAESI...                                                  │
│  token_accessor  abc123...                                                  │
│  token_duration  1h                                                         │
│  token_renewable true                                                       │
│  token_policies  ["default" "app-policy"]                                   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ DEBUG COMMANDS                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Check token details                                                      │
│  vault token lookup <TOKEN>                                                 │
│                                                                             │
│  # Check what policies are attached                                         │
│  vault token lookup -format=json <TOKEN> | jq '.data.policies'             │
│                                                                             │
│  # Check TTL remaining                                                      │
│  vault token lookup -format=json <TOKEN> | jq '.data.ttl'                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 6: Pod Uses Token to Access Secrets

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 6: POD USES TOKEN TO ACCESS SECRETS                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHAT HAPPENS                                                               │
│  ─────────────                                                              │
│  The pod uses the Vault token to read secrets. The token's policies         │
│  determine what paths the pod can access.                                   │
│                                                                             │
│  USAGE                                                                      │
│  ─────                                                                      │
│  # Set the token                                                            │
│  export VAULT_TOKEN=hvs.CAESI...                                           │
│                                                                             │
│  # Read a secret                                                            │
│  vault kv get secret/myapp/config                                          │
│                                                                             │
│  POLICY EXAMPLE                                                             │
│  ──────────────                                                             │
│  # This policy allows reading from secret/myapp/*                           │
│  path "secret/data/myapp/*" {                                               │
│    capabilities = ["read", "list"]                                          │
│  }                                                                          │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WHAT CAN GO WRONG                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Problem                      │ Cause                    │ Solution         │
│  ────────────────────────────│─────────────────────────│─────────────────  │
│  "permission denied"          │ Policy doesn't allow     │ Update policy    │
│  "token expired"              │ TTL passed               │ Re-authenticate  │
│  "missing client token"       │ Token not set            │ Set VAULT_TOKEN  │
│  Can read some paths, not     │ Policy too restrictive   │ Check policy     │
│  others                       │                          │ paths            │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ SUCCESS LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ====== Secret Path ======                                                  │
│  Key                Value                                                   │
│  ---                -----                                                   │
│  username           admin                                                   │
│  password           secret123                                               │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ FAILURE LOOKS LIKE                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Policy doesn't grant access                                              │
│  Error reading secret/data/other/path: permission denied                    │
│                                                                             │
│  # Token expired                                                            │
│  Error reading secret/data/myapp/config: permission denied                  │
│  (Note: Same error as policy issue - check token validity first)            │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ DEBUG COMMANDS                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Check what the token can access                                          │
│  vault token capabilities <TOKEN> secret/data/myapp/config                 │
│  # Expected: read, list (or whatever the policy grants)                     │
│                                                                             │
│  # Read the policy                                                          │
│  vault policy read <POLICY-NAME>                                           │
│                                                                             │
│  # Check if token is still valid                                            │
│  vault token lookup <TOKEN>                                                 │
│                                                                             │
│  # Check token TTL                                                          │
│  vault token lookup -format=json <TOKEN> | jq '.data.ttl'                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Deep Dives

### RBAC and TokenReview

Understanding why Vault needs specific Kubernetes RBAC permissions.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    RBAC FOR VAULT KUBERNETES AUTH                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHY DOES VAULT NEED RBAC?                                                  │
│  ─────────────────────────                                                  │
│  Vault needs to call the TokenReview API to validate pod JWTs.              │
│  This requires a ServiceAccount with the right permissions.                 │
│                                                                             │
│  THE RELATIONSHIP                                                           │
│  ────────────────                                                           │
│                                                                             │
│  ┌──────────────────┐                                                       │
│  │ ServiceAccount   │  vault-auth (in kube-system)                          │
│  │                  │  → Provides token_reviewer_jwt to Vault               │
│  └────────┬─────────┘                                                       │
│           │ bound by                                                        │
│           ▼                                                                 │
│  ┌──────────────────┐                                                       │
│  │ ClusterRole      │  system:auth-delegator                                │
│  │ Binding          │  → Grants permission to create tokenreviews           │
│  └────────┬─────────┘                                                       │
│           │ references                                                      │
│           ▼                                                                 │
│  ┌──────────────────┐                                                       │
│  │ ClusterRole      │  system:auth-delegator (built-in)                     │
│  │                  │  → Allows: tokenreviews.create                        │
│  └──────────────────┘     subjectaccessreviews.create                       │
│                                                                             │
│  REQUIRED KUBERNETES MANIFESTS                                              │
│  ─────────────────────────────                                              │
│                                                                             │
│  # 1. ServiceAccount for Vault to use                                       │
│  apiVersion: v1                                                             │
│  kind: ServiceAccount                                                       │
│  metadata:                                                                  │
│    name: vault-auth                                                         │
│    namespace: kube-system                                                   │
│                                                                             │
│  # 2. ClusterRoleBinding to grant permissions                               │
│  apiVersion: rbac.authorization.k8s.io/v1                                   │
│  kind: ClusterRoleBinding                                                   │
│  metadata:                                                                  │
│    name: vault-auth-tokenreview                                             │
│  roleRef:                                                                   │
│    apiGroup: rbac.authorization.k8s.io                                      │
│    kind: ClusterRole                                                        │
│    name: system:auth-delegator     ◄── Built-in role                       │
│  subjects:                                                                  │
│  - kind: ServiceAccount                                                     │
│    name: vault-auth                                                         │
│    namespace: kube-system                                                   │
│                                                                             │
│  VERIFYING RBAC IS CORRECT                                                  │
│  ─────────────────────────                                                  │
│                                                                             │
│  # Check ServiceAccount exists                                              │
│  kubectl get sa vault-auth -n kube-system                                  │
│                                                                             │
│  # Check ClusterRoleBinding exists and is correct                           │
│  kubectl describe clusterrolebinding vault-auth-tokenreview                 │
│                                                                             │
│  # Test if SA can create tokenreviews                                       │
│  kubectl auth can-i create tokenreviews \                                   │
│    --as=system:serviceaccount:kube-system:vault-auth                       │
│  # Expected: yes                                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Issuer and Audience

The most common source of authentication failures in Kubernetes 1.21+.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       ISSUER AND AUDIENCE EXPLAINED                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHAT ARE THEY?                                                             │
│  ──────────────                                                             │
│                                                                             │
│  JWT Token contains:                                                        │
│  {                                                                          │
│    "iss": "https://kubernetes.default.svc",    ◄── ISSUER                  │
│    "aud": ["https://kubernetes.default.svc"],  ◄── AUDIENCE                │
│    ...                                                                      │
│  }                                                                          │
│                                                                             │
│  • ISSUER (iss): Who created/signed the token                               │
│  • AUDIENCE (aud): Who the token is intended for                            │
│                                                                             │
│  WHY DO THEY CAUSE PROBLEMS?                                                │
│  ───────────────────────────                                                │
│                                                                             │
│  1. Different K8s environments have different issuers:                      │
│                                                                             │
│     Environment          │ Typical Issuer                                   │
│     ─────────────────────│───────────────────────────────────────────       │
│     Self-hosted          │ https://kubernetes.default.svc                   │
│     Minikube             │ https://kubernetes.default.svc.cluster.local     │
│     EKS                  │ https://oidc.eks.REGION.amazonaws.com/id/XXX    │
│     GKE                  │ https://container.googleapis.com/v1/projects/... │
│     AKS                  │ https://REGION.oic.prod-aks.azure.com/...       │
│                                                                             │
│  2. Vault validates the issuer by default (pre-1.9)                         │
│  3. Kubernetes 1.21+ uses "bound" tokens with audiences                     │
│                                                                             │
│  COMMON ERRORS                                                              │
│  ─────────────                                                              │
│                                                                             │
│  # Issuer mismatch                                                          │
│  error="claim \"iss\" is invalid"                                          │
│                                                                             │
│  # Audience mismatch                                                        │
│  error="aud claim does not match expected audience"                        │
│                                                                             │
│  SOLUTIONS                                                                  │
│  ─────────                                                                  │
│                                                                             │
│  Option 1: Disable issuer validation (simpler)                              │
│  ─────────────────────────────────────────────                              │
│  vault write auth/kubernetes/config \                                       │
│    disable_iss_validation=true \                                           │
│    ...                                                                      │
│                                                                             │
│  Option 2: Set the correct issuer (more secure)                             │
│  ──────────────────────────────────────────────                             │
│  # First, find the actual issuer                                            │
│  kubectl exec <POD> -- cat /var/run/secrets/.../token | \                  │
│    cut -d. -f2 | base64 -d | jq -r '.iss'                                  │
│                                                                             │
│  # Then configure Vault                                                     │
│  vault write auth/kubernetes/config \                                       │
│    issuer="<actual-issuer>" \                                              │
│    ...                                                                      │
│                                                                             │
│  Option 3: For audience issues, configure audience                          │
│  ─────────────────────────────────────────────────                          │
│  vault write auth/kubernetes/config \                                       │
│    audience="https://kubernetes.default.svc" \                             │
│    ...                                                                      │
│                                                                             │
│  FINDING THE ISSUER FOR YOUR ENVIRONMENT                                    │
│  ───────────────────────────────────────                                    │
│                                                                             │
│  # Decode a pod's token and check iss                                       │
│  kubectl exec <POD> -n <NS> -- \                                           │
│    cat /var/run/secrets/kubernetes.io/serviceaccount/token | \             │
│    cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.iss'                      │
│                                                                             │
│  # For EKS specifically                                                     │
│  aws eks describe-cluster --name <CLUSTER> \                               │
│    --query 'cluster.identity.oidc.issuer' --output text                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Token Types: Legacy vs Projected

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TOKEN TYPES: LEGACY vs PROJECTED                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  LEGACY TOKENS (Pre-Kubernetes 1.21)                                        │
│  ───────────────────────────────────                                        │
│                                                                             │
│  • Stored as Secrets in the cluster                                         │
│  • Never expire (infinite lifetime)                                         │
│  • Not bound to any specific pod                                            │
│  • Auto-mounted to all pods using the SA                                    │
│  • Security concern: if leaked, valid forever                               │
│                                                                             │
│  # Creating a legacy token (still possible)                                 │
│  apiVersion: v1                                                             │
│  kind: Secret                                                               │
│  metadata:                                                                  │
│    name: my-sa-token                                                        │
│    annotations:                                                             │
│      kubernetes.io/service-account.name: my-sa                              │
│  type: kubernetes.io/service-account-token                                  │
│                                                                             │
│  PROJECTED TOKENS (Kubernetes 1.21+, default)                               │
│  ────────────────────────────────────────────                               │
│                                                                             │
│  • Generated on-demand by kubelet                                           │
│  • Short-lived (default: 1 hour, max: 48 hours)                             │
│  • Bound to specific pod (invalidated when pod dies)                        │
│  • Have audience claims                                                     │
│  • More secure                                                              │
│                                                                             │
│  COMPARISON                                                                 │
│  ──────────                                                                 │
│                                                                             │
│  Feature              │ Legacy          │ Projected                         │
│  ─────────────────────│─────────────────│─────────────────────              │
│  Lifetime             │ Never expires   │ Short-lived (1-48h)              │
│  Storage              │ K8s Secret      │ Generated on-demand              │
│  Pod binding          │ No              │ Yes (dies with pod)              │
│  Audience             │ No              │ Yes                               │
│  Auto-rotation        │ No              │ Yes (kubelet refreshes)          │
│  Security             │ Lower           │ Higher                            │
│                                                                             │
│  HOW TO TELL WHICH TYPE YOU HAVE                                            │
│  ───────────────────────────────                                            │
│                                                                             │
│  # Decode token and check for exp claim                                     │
│  kubectl exec <POD> -- cat /var/run/secrets/.../token | \                  │
│    cut -d. -f2 | base64 -d | jq '.exp'                                     │
│                                                                             │
│  • If exp exists → Projected token                                          │
│  • If exp is null/missing → Legacy token                                    │
│                                                                             │
│  IMPLICATIONS FOR VAULT                                                     │
│  ──────────────────────                                                     │
│                                                                             │
│  • Projected tokens: Need audience configuration in some cases              │
│  • Projected tokens: May need issuer configuration                          │
│  • Legacy tokens: Simpler but less secure                                   │
│  • token_reviewer_jwt: Best to use legacy token for stability               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Environment-Specific Considerations

### Self-Hosted Kubernetes

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ SELF-HOSTED KUBERNETES                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  kubernetes_host: https://<api-server-ip>:6443                              │
│  issuer: Usually https://kubernetes.default.svc                             │
│  CA cert: From /etc/kubernetes/pki/ca.crt                                   │
│                                                                             │
│  TYPICAL CONFIG                                                             │
│  vault write auth/kubernetes/config \                                       │
│    kubernetes_host="https://10.0.0.1:6443" \                               │
│    kubernetes_ca_cert=@/path/to/ca.crt \                                   │
│    token_reviewer_jwt="..." \                                              │
│    disable_iss_validation=true                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Amazon EKS

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ AMAZON EKS                                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  kubernetes_host: https://<cluster-endpoint>.eks.amazonaws.com              │
│  issuer: https://oidc.eks.<region>.amazonaws.com/id/<id>                   │
│  CA cert: Usually from aws eks describe-cluster                             │
│                                                                             │
│  GETTING EKS VALUES                                                         │
│  # Get cluster endpoint                                                     │
│  aws eks describe-cluster --name <CLUSTER> \                               │
│    --query 'cluster.endpoint' --output text                                │
│                                                                             │
│  # Get OIDC issuer                                                          │
│  aws eks describe-cluster --name <CLUSTER> \                               │
│    --query 'cluster.identity.oidc.issuer' --output text                    │
│                                                                             │
│  # Get CA cert (base64)                                                     │
│  aws eks describe-cluster --name <CLUSTER> \                               │
│    --query 'cluster.certificateAuthority.data' --output text               │
│                                                                             │
│  TYPICAL CONFIG                                                             │
│  vault write auth/kubernetes/config \                                       │
│    kubernetes_host="https://XXX.eks.amazonaws.com" \                       │
│    kubernetes_ca_cert="$(aws eks describe-cluster ... | base64 -d)" \     │
│    issuer="https://oidc.eks.us-east-1.amazonaws.com/id/XXX"               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Google GKE

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ GOOGLE GKE                                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  kubernetes_host: https://<cluster-endpoint>                                │
│  issuer: Varies - check your cluster configuration                          │
│  CA cert: From gcloud or cluster config                                     │
│                                                                             │
│  GETTING GKE VALUES                                                         │
│  # Get cluster endpoint                                                     │
│  gcloud container clusters describe <CLUSTER> \                            │
│    --zone <ZONE> --format='get(endpoint)'                                  │
│                                                                             │
│  # Get CA cert                                                              │
│  gcloud container clusters describe <CLUSTER> \                            │
│    --zone <ZONE> --format='get(masterAuth.clusterCaCertificate)'          │
│                                                                             │
│  TYPICAL CONFIG                                                             │
│  vault write auth/kubernetes/config \                                       │
│    kubernetes_host="https://XXX.XXX.XXX.XXX" \                             │
│    kubernetes_ca_cert="..." \                                              │
│    disable_iss_validation=true                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Azure AKS

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ AZURE AKS                                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  kubernetes_host: https://<cluster-name>-dns-<hash>.hcp.<region>.azmk8s.io │
│  issuer: https://<region>.oic.prod-aks.azure.com/<tenant-id>/<id>/         │
│                                                                             │
│  GETTING AKS VALUES                                                         │
│  # Get cluster info                                                         │
│  az aks show --resource-group <RG> --name <CLUSTER> --query fqdn          │
│                                                                             │
│  # Get OIDC issuer (if enabled)                                             │
│  az aks show --resource-group <RG> --name <CLUSTER> \                      │
│    --query 'oidcIssuerProfile.issuerUrl' -o tsv                            │
│                                                                             │
│  TYPICAL CONFIG                                                             │
│  vault write auth/kubernetes/config \                                       │
│    kubernetes_host="https://..." \                                         │
│    kubernetes_ca_cert="..." \                                              │
│    disable_iss_validation=true                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### This Lab (Minikube + ngrok)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ THIS LAB: MINIKUBE + NGROK                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ARCHITECTURE                                                               │
│  Vault (AWS) → ngrok URL → ngrok tunnel → Minikube API                     │
│                                                                             │
│  KEY DIFFERENCES FROM PRODUCTION                                            │
│  • kubernetes_host = ngrok URL (not direct K8s API)                         │
│  • kubernetes_ca_cert = NOT USED (ngrok handles TLS)                        │
│  • disable_local_ca_jwt = true (Vault not in cluster)                       │
│  • disable_iss_validation = true (issuer varies)                            │
│                                                                             │
│  CONFIG                                                                     │
│  vault write auth/kubernetes/config \                                       │
│    kubernetes_host="https://abc123.ngrok-free.app" \                       │
│    token_reviewer_jwt="..." \                                              │
│    disable_iss_validation=true \                                           │
│    disable_local_ca_jwt=true                                               │
│                                                                             │
│  ⚠️  NOT FOR PRODUCTION                                                     │
│  • ngrok URL is public                                                      │
│  • No proper TLS verification                                               │
│  • URL changes when ngrok restarts                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting by Error Message

Quick lookup - find your exact error:

| Error Message | Step | Root Cause | Solution |
|---------------|------|------------|----------|
| `permission denied` | 4 | SA or namespace not in role's bound list | Add SA/NS to role |
| `service account name not authorized` | 4 | SA name doesn't match | Check exact SA name |
| `namespace not authorized` | 4 | Namespace doesn't match | Check namespace |
| `could not validate JWT` | 3 | TokenReview failed | Check K8s auth config |
| `connection refused` | 3 | Vault can't reach K8s API | Check kubernetes_host |
| `no such host` | 3 | DNS resolution failed | Check kubernetes_host URL |
| `claim "iss" is invalid` | 3 | Issuer mismatch | Set issuer or disable validation |
| `aud claim mismatch` | 3 | Audience mismatch | Configure audience |
| `token is expired` | 3 | JWT expired | Restart pod for new token |
| `forbidden` | 3 | Missing RBAC | Add system:auth-delegator |
| `no handler for route` | 2 | K8s auth not enabled | `vault auth enable kubernetes` |
| `role "X" not found` | 2 | Role doesn't exist | Create the role |
| `tls: failed to verify` | 2/3 | Certificate issue | Check TLS config |

---

## Configuration Reference

### Auth Config Parameters

```bash
vault write auth/kubernetes/config \
    kubernetes_host="..."           # Required: K8s API URL
    token_reviewer_jwt="..."        # JWT for TokenReview calls
    kubernetes_ca_cert="..."        # CA cert for TLS verification
    issuer="..."                    # Expected JWT issuer
    audience="..."                  # Expected JWT audience
    disable_iss_validation=false    # Skip issuer check
    disable_local_ca_jwt=false      # Don't use local CA/JWT
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `kubernetes_host` | Yes | URL of K8s API server |
| `token_reviewer_jwt` | Depends | JWT for calling TokenReview (required if Vault outside cluster) |
| `kubernetes_ca_cert` | No | CA cert to verify K8s API TLS |
| `issuer` | No | Expected issuer claim in JWT |
| `audience` | No | Expected audience claim in JWT |
| `disable_iss_validation` | No | Set `true` to skip issuer check (common fix) |
| `disable_local_ca_jwt` | No | Set `true` if Vault is outside the cluster |

### Role Parameters

```bash
vault write auth/kubernetes/role/my-role \
    bound_service_account_names="..."      # Required: Allowed SA names
    bound_service_account_namespaces="..." # Required: Allowed namespaces
    policies="..."                         # Policies to attach
    ttl="1h"                               # Token TTL
    max_ttl="24h"                          # Max renewable TTL
    audience="..."                         # Override audience for this role
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `bound_service_account_names` | Yes | Comma-separated list of allowed SA names (`*` for any) |
| `bound_service_account_namespaces` | Yes | Comma-separated list of allowed namespaces (`*` for any) |
| `policies` | No | Policies to attach to tokens |
| `ttl` | No | Token TTL (default: system default) |
| `max_ttl` | No | Maximum renewable TTL |
| `audience` | No | Audience to validate (overrides auth config) |

---

## See Also

- [General K8s Auth Troubleshooting](k8s-auth-troubleshooting-general.md)
- [Vault Agent Injector Guide](vault-agent-injector.md)
- [Certificate Inspection Script](../scripts/06-inspect-certificates.sh)
- [Official Vault K8s Auth Docs](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
