# Vault Agent Injector - Troubleshooting & Reference Guide

The Vault Agent Injector is a Kubernetes mutating webhook that automatically injects Vault Agent containers into pods. This guide covers how it works, how to troubleshoot it, and common issues encountered in production.

---

## Table of Contents

1. [Quick Diagnostic Flowchart](#quick-diagnostic-flowchart)
2. [How It Works](#how-it-works)
3. [Understanding Templates](#understanding-templates)
4. [Stage-by-Stage Troubleshooting](#stage-by-stage-troubleshooting)
5. [Error Message Reference](#error-message-reference)
6. [Log Interpretation Guide](#log-interpretation-guide)
7. [Common Scenarios & Fixes](#common-scenarios--fixes)
8. [Annotations Reference](#annotations-reference)
9. [Example Configurations](#example-configurations)
10. [Health Check Commands](#health-check-commands)

---

## Quick Diagnostic Flowchart

Use this for rapid triage during support calls:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     VAULT AGENT INJECTOR DIAGNOSTIC                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  What's the pod status?                                                     │
│  $ kubectl get pod <pod> -n <ns>                                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                                                                     │    │
│  │  Pod has NO vault-agent containers?                                 │    │
│  │  └──► STAGE 1: Webhook not firing                                   │    │
│  │       • Is injector pod running?                                    │    │
│  │       • Are annotations correct?                                    │    │
│  │       • Is namespace excluded?                                      │    │
│  │                                                                     │    │
│  ├─────────────────────────────────────────────────────────────────────┤    │
│  │                                                                     │    │
│  │  Pod stuck in Init:0/1 or Init:0/2?                                 │    │
│  │  └──► STAGE 2: Init container failing                               │    │
│  │       $ kubectl logs <pod> -c vault-agent-init -n <ns>              │    │
│  │       • Can't reach Vault?                                          │    │
│  │       • Auth failing?                                               │    │
│  │       • Secret path wrong?                                          │    │
│  │                                                                     │    │
│  ├─────────────────────────────────────────────────────────────────────┤    │
│  │                                                                     │    │
│  │  Pod running but /vault/secrets/ empty or wrong?                    │    │
│  │  └──► STAGE 3: Template rendering issue                             │    │
│  │       • Check template syntax                                       │    │
│  │       • KV v1 vs v2 mismatch?                                       │    │
│  │       • Secret exists but fields wrong?                             │    │
│  │                                                                     │    │
│  ├─────────────────────────────────────────────────────────────────────┤    │
│  │                                                                     │    │
│  │  Sidecar crashlooping or secrets not refreshing?                    │    │
│  │  └──► STAGE 4: Sidecar issues                                       │    │
│  │       $ kubectl logs <pod> -c vault-agent -n <ns>                   │    │
│  │       • Token renewal failing?                                      │    │
│  │       • Resource limits hit?                                        │    │
│  │                                                                     │    │
│  ├─────────────────────────────────────────────────────────────────────┤    │
│  │                                                                     │    │
│  │  App can't read secrets (but files exist)?                          │    │
│  │  └──► STAGE 5: Application consumption                              │    │
│  │       • File permissions?                                           │    │
│  │       • Wrong file format?                                          │    │
│  │       • App looking in wrong path?                                  │    │
│  │                                                                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## How It Works

### Injection Flow

```
┌───────────────────────────────────────────────────────────────────────────┐
│                      VAULT AGENT INJECTION FLOW                           │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  1. User creates Pod with annotations                                     │
│     ┌─────────────────────────────────┐                                   │
│     │ Pod Spec                        │                                   │
│     │ annotations:                    │                                   │
│     │   vault...agent-inject: "true"  │                                   │
│     │   vault...role: "my-role"       │                                   │
│     └───────────────┬─────────────────┘                                   │
│                     │                                                     │
│                     ▼                                                     │
│  2. K8s API Server intercepts (Admission Control)                         │
│     ┌─────────────────────────────────┐                                   │
│     │ Mutating Admission Webhook      │                                   │
│     │ "Should I modify this pod?"     │                                   │
│     └───────────────┬─────────────────┘                                   │
│                     │                                                     │
│                     ▼                                                     │
│  3. Vault Agent Injector modifies Pod spec                                │
│     ┌─────────────────────────────────┐                                   │
│     │ Adds:                           │                                   │
│     │  • vault-agent-init container   │                                   │
│     │  • vault-agent sidecar          │                                   │
│     │  • Shared volume (/vault/secrets)│                                  │
│     │  • Environment variables        │                                   │
│     └───────────────┬─────────────────┘                                   │
│                     │                                                     │
│                     ▼                                                     │
│  4. Pod starts with injected containers                                   │
│     ┌─────────────────────────────────────────────────────┐               │
│     │  Pod                                                │               │
│     │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │               │
│     │  │ vault-agent │  │ vault-agent │  │ your-app    │  │               │
│     │  │ -init       │  │ (sidecar)   │  │             │  │               │
│     │  │             │  │             │  │             │  │               │
│     │  │ Runs FIRST  │  │ Runs        │  │ Reads from  │  │               │
│     │  │ Gets secrets│  │ continuously│  │ /vault/     │  │               │
│     │  │ Then exits  │  │ Refreshes   │  │ secrets/    │  │               │
│     │  └─────────────┘  └─────────────┘  └─────────────┘  │               │
│     │         │                │                ▲         │               │
│     │         └────────────────┴────────────────┘         │               │
│     │                  Shared Volume                      │               │
│     │                  /vault/secrets/                    │               │
│     └─────────────────────────────────────────────────────┘               │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

### What Gets Injected (Before/After)

Understanding what the injector adds helps diagnose when mutation fails.

**BEFORE (user's original pod spec):**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-role"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
spec:
  serviceAccountName: my-sa
  containers:
  - name: app
    image: my-app:latest
```

**AFTER (mutated by injector):**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-role"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
    vault.hashicorp.com/agent-inject-status: "injected"  # ◄── ADDED
spec:
  serviceAccountName: my-sa
  initContainers:                                        # ◄── ADDED
  - name: vault-agent-init
    image: hashicorp/vault:1.15.0
    # ... vault agent config ...
  containers:
  - name: app
    image: my-app:latest
    volumeMounts:                                        # ◄── ADDED
    - name: vault-secrets
      mountPath: /vault/secrets
  - name: vault-agent                                    # ◄── ADDED
    image: hashicorp/vault:1.15.0
    # ... sidecar config ...
  volumes:                                               # ◄── ADDED
  - name: vault-secrets
    emptyDir:
      medium: Memory
```

**Key things to verify:**
```bash
# Check if pod was mutated
kubectl get pod <pod> -n <ns> -o jsonpath='{.metadata.annotations.vault\.hashicorp\.com/agent-inject-status}'
# Should output: "injected"

# List all containers (should see vault-agent)
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].name}'

# List init containers (should see vault-agent-init)
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.initContainers[*].name}'
```

### Why the Sidecar Pattern?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SIDECAR PATTERN EXPLAINED                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WITHOUT SIDECAR (init-only):                                               │
│  ────────────────────────────                                               │
│                                                                             │
│    Pod Start ──► Init gets secrets ──► App runs with static secrets         │
│                                                                             │
│    Problems:                                                                │
│    • Secrets never refresh                                                  │
│    • If Vault rotates a secret, app has stale data                          │
│    • Long-running pods accumulate drift                                     │
│                                                                             │
│  WITH SIDECAR (default):                                                    │
│  ───────────────────────                                                    │
│                                                                             │
│    Pod Start ──► Init gets secrets ──► App runs                             │
│                        │                   │                                │
│                        │              Sidecar runs continuously             │
│                        │                   │                                │
│                        │              Every 5 min (default):                │
│                        │              • Re-authenticate if needed           │
│                        │              • Re-fetch secrets                    │
│                        │              • Update files if changed             │
│                        ▼                   ▼                                │
│                   /vault/secrets/ stays current                             │
│                                                                             │
│  WHEN TO USE INIT-ONLY (agent-pre-populate-only: "true"):                   │
│  ────────────────────────────────────────────────────────                   │
│    • Secrets truly never change (certificates with long TTL)                │
│    • Short-lived batch jobs                                                 │
│    • Resource-constrained environments                                      │
│    • App reads secrets once at startup only                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Injector Pod | `vault` namespace | Watches for annotated pods, runs webhook server |
| MutatingWebhookConfiguration | Cluster-wide | Tells K8s API to send pods to injector |
| vault-agent-init | Injected into pods | Authenticates, fetches secrets, exits |
| vault-agent (sidecar) | Injected into pods | Keeps secrets updated, renews tokens |

---

## Understanding Templates

**This is the #1 source of support issues.** Most template problems come from KV v1 vs v2 confusion.

### KV v1 vs KV v2: The Critical Difference

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    KV VERSION 1 vs VERSION 2                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  KV Version 1:                                                              │
│  ─────────────                                                              │
│  • Secret path: secret/myapp/config                                         │
│  • Template access: {{ .Data.username }}                                    │
│  • Data structure is FLAT                                                   │
│                                                                             │
│    API Response:                                                            │
│    {                                                                        │
│      "data": {                                                              │
│        "username": "admin",        ◄── Direct access                        │
│        "password": "secret123"                                              │
│      }                                                                      │
│    }                                                                        │
│                                                                             │
│  KV Version 2:                                                              │
│  ─────────────                                                              │
│  • Secret path: secret/data/myapp/config    ◄── Note: "data" in path!       │
│  • Template access: {{ .Data.data.username }}   ◄── Note: .Data.data        │
│  • Data structure is NESTED (includes metadata)                             │
│                                                                             │
│    API Response:                                                            │
│    {                                                                        │
│      "data": {                                                              │
│        "data": {                   ◄── Extra nesting!                       │
│          "username": "admin",                                               │
│          "password": "secret123"                                            │
│        },                                                                   │
│        "metadata": {               ◄── KV v2 adds metadata                  │
│          "version": 3,                                                      │
│          "created_time": "..."                                              │
│        }                                                                    │
│      }                                                                      │
│    }                                                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### How to Determine KV Version

```bash
# Method 1: Check the mount options
vault secrets list -detailed | grep <mount-path>
# Look for "version" in Options column

# Method 2: Read a secret and check response structure
vault read secret/myapp/config      # v1: works, returns data directly
vault read secret/data/myapp/config # v2: works, returns data.data

# Method 3: Check mount info
vault read sys/mounts/secret
# Look for "options" → "version"
```

### Template Syntax Quick Reference

**Go Template Basics:**
```yaml
# Whitespace control
{{- ... }}   # Trim whitespace BEFORE
{{ ... -}}   # Trim whitespace AFTER
{{- ... -}}  # Trim both sides

# The "with" block (creates scope, fails gracefully if secret missing)
{{- with secret "path/to/secret" -}}
  # Inside here, . refers to the secret response
  {{ .Data.data.field }}
{{- end }}

# Accessing nested data
{{ .Data.data.username }}     # KV v2
{{ .Data.username }}          # KV v1
```

**Common Template Patterns:**

```yaml
# KV v2 - Environment file
vault.hashicorp.com/agent-inject-template-env: |
  {{- with secret "secret/data/myapp/config" -}}
  export DB_HOST="{{ .Data.data.host }}"
  export DB_USER="{{ .Data.data.username }}"
  export DB_PASS="{{ .Data.data.password }}"
  {{- end }}

# KV v1 - Environment file (note: no .data.data)
vault.hashicorp.com/agent-inject-template-env: |
  {{- with secret "secret/myapp/config" -}}
  export DB_HOST="{{ .Data.host }}"
  export DB_USER="{{ .Data.username }}"
  export DB_PASS="{{ .Data.password }}"
  {{- end }}

# JSON output
vault.hashicorp.com/agent-inject-template-config.json: |
  {{- with secret "secret/data/myapp/config" -}}
  {
    "database": {
      "host": "{{ .Data.data.host }}",
      "username": "{{ .Data.data.username }}",
      "password": "{{ .Data.data.password }}"
    }
  }
  {{- end }}
```

### Common Template Errors

| Error | Cause | Fix |
|-------|-------|-----|
| Empty file output | KV v1/v2 mismatch | Check `.Data.data` vs `.Data` |
| `no secret exists at` | Wrong path | Remove `/data/` for v1, add for v2 |
| `map has no entry for key` | Field doesn't exist | Check secret has that field |
| `executing template: ...` | Syntax error | Check braces, quotes, whitespace |

---

## Stage-by-Stage Troubleshooting

### Stage 1: Webhook Mutation

**Symptoms:**
- Pod is running but has NO vault-agent containers
- No `/vault/secrets/` volume mount
- `agent-inject-status` annotation missing

**Diagnostic Commands:**
```bash
# 1. Is the injector pod running?
kubectl get pods -n vault -l app.kubernetes.io/name=vault-agent-injector
# Should show 1/1 Running

# 2. Is the webhook configured?
kubectl get mutatingwebhookconfiguration | grep vault
# Should show vault-agent-injector-cfg

# 3. Check webhook details
kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg -o yaml | grep -A5 namespaceSelector

# 4. Was the pod mutated?
kubectl get pod <pod> -n <ns> -o jsonpath='{.metadata.annotations}' | jq .
# Look for vault.hashicorp.com/agent-inject-status: "injected"

# 5. Check injector logs for this pod
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector | grep <pod-name>
```

**Common Causes & Solutions:**

| Cause | How to Verify | Solution |
|-------|---------------|----------|
| Injector not running | `kubectl get pods -n vault` | Check injector deployment |
| Namespace excluded | Check webhook namespaceSelector | Remove exclusion or use different ns |
| Annotation typo | Check annotation spelling | Fix: `vault.hashicorp.com/agent-inject` |
| Annotation value wrong | Check value is string "true" | Use `"true"` not `true` |
| Pod created before injector | Check timestamps | Delete and recreate pod |

### Stage 2: Init Container

**Symptoms:**
- Pod stuck in `Init:0/1` or `Init:0/2`
- Init container shows Error or CrashLoopBackOff

**Diagnostic Commands:**
```bash
# 1. Check pod status
kubectl get pod <pod> -n <ns>

# 2. Get init container logs (THE MOST IMPORTANT COMMAND)
kubectl logs <pod> -c vault-agent-init -n <ns>

# 3. Describe pod for events
kubectl describe pod <pod> -n <ns> | tail -20

# 4. Check if Vault is reachable from pod
kubectl exec <pod> -c vault-agent-init -n <ns> -- \
  wget -q -O- $VAULT_ADDR/v1/sys/health 2>/dev/null || echo "Cannot reach Vault"
```

**Common Init Container Errors:**

| Log Message | Cause | Solution |
|-------------|-------|----------|
| `permission denied` | Role doesn't allow this SA/namespace | Check `bound_service_account_names` and `bound_service_account_namespaces` |
| `service account name not authorized` | SA name mismatch | Verify SA matches role config |
| `connection refused` | Can't reach Vault | Check VAULT_ADDR, network policies |
| `no secret exists at` | Wrong secret path | Check path, KV v1 vs v2 |
| `error fetching secret` | Secret doesn't exist | Create the secret in Vault |
| `template error` | Bad template syntax | Check template, see template section |
| `could not validate JWT` | K8s auth issue | Check Vault K8s auth config |

### Stage 3: Secret Rendering

**Symptoms:**
- Init container succeeded (pod is Running)
- `/vault/secrets/` exists but files are empty or have wrong content

**Diagnostic Commands:**
```bash
# 1. Check if files exist
kubectl exec <pod> -n <ns> -- ls -la /vault/secrets/

# 2. Check file contents
kubectl exec <pod> -n <ns> -- cat /vault/secrets/config

# 3. Check template annotation
kubectl get pod <pod> -n <ns> -o yaml | grep -A10 "agent-inject-template"

# 4. Test template manually (if you have vault CLI access)
vault kv get -format=json secret/myapp/config
# Verify the fields exist
```

**Common Causes & Solutions:**

| Issue | Cause | Solution |
|-------|-------|----------|
| Empty file | KV v1/v2 template mismatch | Use `.Data.data.field` for v2 |
| Missing fields | Field name typo | Check exact field names in secret |
| Extra whitespace | Template whitespace | Use `{{-` and `-}}` |
| Wrong format | Template logic error | Simplify and test incrementally |

### Stage 4: Sidecar Operation

**Symptoms:**
- Pod was running fine, then sidecar starts crashlooping
- Secrets not updating when changed in Vault
- Token renewal errors in logs

**Diagnostic Commands:**
```bash
# 1. Check sidecar status
kubectl get pod <pod> -n <ns> -o jsonpath='{.status.containerStatuses[?(@.name=="vault-agent")].state}'

# 2. Get sidecar logs
kubectl logs <pod> -c vault-agent -n <ns>

# 3. Check for restarts
kubectl get pod <pod> -n <ns> -o jsonpath='{.status.containerStatuses[?(@.name=="vault-agent")].restartCount}'

# 4. Check resource usage
kubectl top pod <pod> -n <ns> --containers
```

**Common Sidecar Issues:**

| Issue | Cause | Solution |
|-------|-------|----------|
| Token renewal failed | Token TTL too short, Vault unreachable | Increase TTL, check connectivity |
| OOMKilled | Memory limit too low | Increase sidecar memory limit |
| Secrets not refreshing | Template cache, no changes | Check Vault secret actually changed |
| Crashlooping | Auth failing on renewal | Check K8s auth still valid |

### Stage 5: Application Consumption

**Symptoms:**
- Secrets exist at `/vault/secrets/`
- Application can't read them or parses them incorrectly

**Diagnostic Commands:**
```bash
# 1. Check file permissions
kubectl exec <pod> -n <ns> -- ls -la /vault/secrets/

# 2. Check file contents from app container
kubectl exec <pod> -c <app-container> -n <ns> -- cat /vault/secrets/config

# 3. Check what the app sees
kubectl exec <pod> -c <app-container> -n <ns> -- env | grep -i vault

# 4. Check volume mount
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[?(@.name=="<app>")].volumeMounts}' | jq .
```

**Common Application Issues:**

| Issue | Cause | Solution |
|-------|-------|----------|
| File not found | App looking in wrong path | Default is `/vault/secrets/` |
| Parse error | Template output format wrong | Adjust template to match app expectations |
| Permission denied | File mode issues | Check container user, file permissions |
| Stale data | App caches secrets | App needs to re-read files or watch for changes |

---

## Error Message Reference

Quick lookup for exact error messages:

| Error Message | Stage | Cause | Solution |
|---------------|-------|-------|----------|
| `permission denied` | Init | SA/namespace not in role's bound list | Update role bindings |
| `service account name not authorized` | Init | SA name doesn't match role | Check `bound_service_account_names` |
| `namespace not authorized` | Init | Namespace not in role | Check `bound_service_account_namespaces` |
| `could not validate JWT` | Init | K8s auth misconfigured | Check Vault K8s auth config |
| `connection refused` | Init | Can't reach Vault server | Check VAULT_ADDR, network |
| `no secret exists at` | Init | Wrong path or secret missing | Verify path, create secret |
| `error fetching secret` | Init | Permission or path issue | Check policy, path |
| `template: ... unexpected ...` | Init | Template syntax error | Fix template syntax |
| `map has no entry for key` | Init | Field doesn't exist in secret | Check secret has that field |
| `renewal failed` | Sidecar | Token can't be renewed | Check TTL, connectivity |
| `token expired` | Sidecar | Token TTL passed | Increase TTL in role |
| `OOMKilled` | Sidecar | Memory limit exceeded | Increase memory limit |

---

## Log Interpretation Guide

### Where to Find Logs

```bash
# Injector pod logs (webhook/mutation issues)
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector

# Init container logs (auth/secret fetch issues)
kubectl logs <pod> -c vault-agent-init -n <ns>

# Sidecar logs (renewal/refresh issues)
kubectl logs <pod> -c vault-agent -n <ns>

# Previous container logs (if crashed)
kubectl logs <pod> -c vault-agent --previous -n <ns>
```

### What Normal Logs Look Like

**Successful Init Container:**
```
==> Vault agent started! Log data will stream in below:
==> Vault agent configuration:
...
[INFO] auth.handler: authenticating
[INFO] auth.handler: authentication successful, sending token to sinks
[INFO] sink.file: token written: path=/home/vault/.vault-token
[INFO] template.server: starting template server
[INFO] template.server: (dynamic): destination:/vault/secrets/config
[INFO] template.server: (dynamic): rendered successfully
[INFO] template.server: template server finished
```

**Successful Sidecar (ongoing):**
```
[INFO] auth.handler: renewed auth token
[INFO] template.server: (dynamic): destination:/vault/secrets/config (no change)
[INFO] auth.handler: renewed auth token
...
```

### What Error Logs Look Like

**Permission Denied:**
```
[ERROR] auth.handler: error authenticating:
  error="Error making API request.
  Code: 403. Errors:
  * permission denied"
```

**Wrong Secret Path:**
```
[ERROR] template.server: (dynamic): error rendering template:
  error="error secret/data/wrong/path: no secret exists at secret/data/wrong/path"
```

**Template Error:**
```
[ERROR] template.server: (dynamic): error rendering template:
  error="template: :1: unexpected \"}\" in operand"
```

**Can't Reach Vault:**
```
[ERROR] auth.handler: error authenticating:
  error="Put \"https://vault.example.com:8200/v1/auth/kubernetes/login\":
  dial tcp: lookup vault.example.com: no such host"
```

### Enabling Debug Mode

Add this annotation to get verbose logs:
```yaml
annotations:
  vault.hashicorp.com/log-level: "debug"
```

Then check logs:
```bash
kubectl logs <pod> -c vault-agent-init -n <ns>
kubectl logs <pod> -c vault-agent -n <ns>
```

---

## Common Scenarios & Fixes

### Scenario 1: Customer Using KV v2 Path with v1 Template

**Symptom:** Secrets file is empty, no errors in logs.

**Diagnosis:**
```bash
# Check secret path in annotation
kubectl get pod <pod> -n <ns> -o yaml | grep agent-inject-secret
# Shows: secret/data/myapp/config (v2 path)

# Check template
kubectl get pod <pod> -n <ns> -o yaml | grep -A5 agent-inject-template
# Shows: {{ .Data.username }}  ← Missing .data!
```

**Fix:** Change template from `.Data.username` to `.Data.data.username`

### Scenario 2: ServiceAccount in Wrong Namespace

**Symptom:** `permission denied` in init container logs.

**Diagnosis:**
```bash
# Check pod's namespace
kubectl get pod <pod> -o jsonpath='{.metadata.namespace}'
# Returns: production

# Check Vault role
vault read auth/kubernetes/role/my-role
# bound_service_account_namespaces: [staging]  ← Wrong!
```

**Fix:**
```bash
vault write auth/kubernetes/role/my-role \
  bound_service_account_namespaces="production"
```

### Scenario 3: Vault Address Not Reachable

**Symptom:** `connection refused` or timeout in init container logs.

**Diagnosis:**
```bash
# Check what Vault address is configured
kubectl get pod <pod> -n <ns> -o yaml | grep -i vault_addr

# Test connectivity from cluster
kubectl run test --rm -it --image=curlimages/curl -- \
  curl -s http://vault.vault.svc:8200/v1/sys/health
```

**Common fixes:**
- Wrong service name/namespace
- Network policy blocking traffic
- Vault not exposing correct port
- TLS issues (try http vs https)

### Scenario 4: Token TTL Too Short

**Symptom:** Sidecar keeps re-authenticating or fails after some time.

**Diagnosis:**
```bash
# Check role TTL
vault read auth/kubernetes/role/my-role
# ttl: 5m  ← Very short

# Check sidecar logs for frequent renewals
kubectl logs <pod> -c vault-agent -n <ns> | grep -i renew
```

**Fix:**
```bash
vault write auth/kubernetes/role/my-role \
  ttl=1h \
  max_ttl=24h
```

### Scenario 5: Template Producing Empty Output

**Symptom:** File exists but is empty or has only whitespace.

**Diagnosis:**
```bash
# Check raw secret
vault kv get secret/myapp/config
# Verify fields exist and have values

# Check template
kubectl get pod <pod> -n <ns> -o yaml | grep -A10 agent-inject-template
# Look for:
#  - Typos in field names
#  - Wrong .Data vs .Data.data
#  - Conditional that evaluates to false
```

**Fix:** Test template incrementally:
```yaml
# Start simple
vault.hashicorp.com/agent-inject-template-test: |
  {{- with secret "secret/data/myapp/config" -}}
  DEBUG: {{ . }}
  {{- end }}
```

---

## Annotations Reference

### Required Annotations

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"                    # Enable injection
  vault.hashicorp.com/role: "my-role"                         # Vault role
  vault.hashicorp.com/agent-inject-secret-NAME: "path"        # Secret to inject
```

### Common Annotations

```yaml
annotations:
  # === BASIC ===
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "my-role"

  # === SECRETS ===
  vault.hashicorp.com/agent-inject-secret-config.txt: "secret/data/myapp/config"
  vault.hashicorp.com/agent-inject-secret-creds.json: "secret/data/myapp/creds"

  # === TEMPLATES ===
  vault.hashicorp.com/agent-inject-template-config.txt: |
    {{- with secret "secret/data/myapp/config" -}}
    username={{ .Data.data.username }}
    password={{ .Data.data.password }}
    {{- end }}

  # === BEHAVIOR ===
  vault.hashicorp.com/agent-pre-populate-only: "true"    # No sidecar
  vault.hashicorp.com/preserve-secret-case: "true"       # Keep filename case

  # === AUTH ===
  vault.hashicorp.com/auth-path: "auth/kubernetes"       # Custom auth path
  vault.hashicorp.com/namespace: "admin"                 # Vault Enterprise namespace

  # === DEBUGGING ===
  vault.hashicorp.com/log-level: "debug"                 # Verbose logging
```

### All Available Annotations

| Annotation | Default | Description |
|------------|---------|-------------|
| `agent-inject` | `false` | Enable injection |
| `role` | - | Vault role to use |
| `agent-inject-secret-<name>` | - | Secret path to inject |
| `agent-inject-template-<name>` | - | Custom template for secret |
| `agent-pre-populate` | `true` | Run init container |
| `agent-pre-populate-only` | `false` | Only init, no sidecar |
| `agent-init-first` | `false` | Run vault-agent-init first |
| `agent-inject-token` | `false` | Inject Vault token file |
| `agent-inject-command` | - | Command after secrets render |
| `auth-path` | `auth/kubernetes` | Auth method path |
| `namespace` | - | Vault namespace (Enterprise) |
| `service` | - | Vault service address |
| `log-level` | `info` | Agent log level |
| `log-format` | `standard` | Log format |

---

## Example Configurations

### Simple Secret Injection

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-simple
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-role"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
spec:
  serviceAccountName: my-sa
  containers:
  - name: app
    image: my-app:latest
    # Secret at /vault/secrets/config
```

### Init-Only (No Sidecar)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-init-only
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-role"
    vault.hashicorp.com/agent-pre-populate-only: "true"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
spec:
  serviceAccountName: my-sa
  containers:
  - name: app
    image: my-app:latest
```

### With Custom Template

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-template
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-role"
    vault.hashicorp.com/agent-inject-secret-env: "secret/data/myapp/config"
    vault.hashicorp.com/agent-inject-template-env: |
      {{- with secret "secret/data/myapp/config" -}}
      export DB_HOST="{{ .Data.data.host }}"
      export DB_USER="{{ .Data.data.username }}"
      export DB_PASS="{{ .Data.data.password }}"
      {{- end }}
spec:
  serviceAccountName: my-sa
  containers:
  - name: app
    image: my-app:latest
    command: ["/bin/sh", "-c"]
    args: ["source /vault/secrets/env && ./start.sh"]
```

### Debug Pod (All Debug Options)

Use this configuration to troubleshoot issues:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: debug-pod
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-role"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
    # DEBUG OPTIONS
    vault.hashicorp.com/log-level: "debug"
    vault.hashicorp.com/agent-inject-token: "true"  # Also inject token file
spec:
  serviceAccountName: my-sa
  containers:
  - name: debug
    image: alpine:latest
    command: ["/bin/sh", "-c", "sleep 3600"]
```

Then debug with:
```bash
kubectl logs debug-pod -c vault-agent-init
kubectl logs debug-pod -c vault-agent
kubectl exec debug-pod -- ls -la /vault/secrets/
kubectl exec debug-pod -- cat /vault/secrets/config
kubectl exec debug-pod -- cat /home/vault/.vault-token  # If token injection enabled
```

---

## Health Check Commands

Copy-paste these for quick diagnostics:

```bash
# ========================================
# INJECTOR HEALTH
# ========================================

# Is injector running?
kubectl get pods -n vault -l app.kubernetes.io/name=vault-agent-injector

# Is webhook registered?
kubectl get mutatingwebhookconfiguration | grep vault

# Injector logs
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector --tail=50

# ========================================
# POD MUTATION CHECK
# ========================================

# Was pod mutated?
kubectl get pod <POD> -n <NS> -o jsonpath='{.metadata.annotations.vault\.hashicorp\.com/agent-inject-status}'

# List containers (should include vault-agent)
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.containers[*].name}'

# List init containers (should include vault-agent-init)
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.initContainers[*].name}'

# ========================================
# INIT CONTAINER DEBUG
# ========================================

# Init container logs (MOST USEFUL)
kubectl logs <POD> -c vault-agent-init -n <NS>

# Init container status
kubectl get pod <POD> -n <NS> -o jsonpath='{.status.initContainerStatuses[*].state}'

# ========================================
# SIDECAR DEBUG
# ========================================

# Sidecar logs
kubectl logs <POD> -c vault-agent -n <NS>

# Sidecar restarts
kubectl get pod <POD> -n <NS> -o jsonpath='{.status.containerStatuses[?(@.name=="vault-agent")].restartCount}'

# ========================================
# SECRETS CHECK
# ========================================

# List secret files
kubectl exec <POD> -n <NS> -- ls -la /vault/secrets/

# Read secret content
kubectl exec <POD> -n <NS> -- cat /vault/secrets/config

# ========================================
# VAULT ROLE CHECK
# ========================================

# Read role config
vault read auth/kubernetes/role/<ROLE>

# Check what SA/NS are allowed
vault read -format=json auth/kubernetes/role/<ROLE> | jq '.data | {bound_service_account_names, bound_service_account_namespaces}'
```

---

## See Also

- [Vault Agent Injector Docs](https://developer.hashicorp.com/vault/docs/platform/k8s/injector)
- [Vault Agent Template Reference](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent/template)
- [General K8s Auth Troubleshooting](k8s-auth-troubleshooting-general.md)
- [Certificate Inspection Script](../scripts/06-inspect-certificates.sh)
