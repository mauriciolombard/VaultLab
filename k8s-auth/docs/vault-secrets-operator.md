# Vault Secrets Operator (VSO) Guide

This document explains the Vault Secrets Operator integration in this lab, including architecture, authentication flow, configuration, and troubleshooting.

## Table of Contents

1. [Overview](#overview)
2. [VSO vs Agent Injector](#vso-vs-agent-injector)
3. [Architecture](#architecture)
4. [Authentication Flow](#authentication-flow)
5. [CRD Hierarchy](#crd-hierarchy)
6. [Configuration Reference](#configuration-reference)
7. [Secret Rotation](#secret-rotation)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### What is VSO?

The Vault Secrets Operator (VSO) is a Kubernetes operator that synchronizes secrets from HashiCorp Vault into native Kubernetes Secrets. Unlike the Agent Injector (which uses sidecar containers), VSO runs as a single controller that manages secrets for the entire cluster.

### Key Concepts

| Term | Description |
|------|-------------|
| **Operator** | A Kubernetes controller that watches Custom Resource Definitions (CRDs) and reconciles state |
| **VaultConnection** | CRD defining how to connect to Vault (address, TLS settings) |
| **VaultAuth** | CRD defining how VSO authenticates to Vault |
| **VaultStaticSecret** | CRD defining which Vault secrets to sync to K8s Secrets |
| **Destination Secret** | The native Kubernetes Secret created/managed by VSO |

### When to Use VSO

Use VSO when you want:
- Native Kubernetes Secret consumption (envFrom, volumeMount)
- Central management of secrets across the cluster
- Lower resource overhead (no sidecar per pod)
- Kubernetes-native patterns (CRDs, kubectl, GitOps)

Use Agent Injector when you want:
- Advanced templating with multiple secrets
- Ephemeral-only secrets (never stored in etcd)
- Broader authentication method support

---

## VSO vs Agent Injector

### Comparison Table

| Aspect | Agent Injector | VSO |
|--------|---------------|-----|
| **Deployment Model** | Mutating webhook + sidecar per pod | Single operator deployment |
| **Secret Storage** | Ephemeral (memory only) | K8s Secret (etcd) |
| **Secret Delivery** | Files in `/vault/secrets/` | envFrom, volumeMount, or both |
| **Pod Modifications** | Injects init + sidecar containers | None (uses standard K8s patterns) |
| **Templating** | Full Go template support | SecretTransformation CRDs |
| **Auth Methods** | K8s + many auto-auth methods | K8s, JWT, AppRole, AWS, GCP |
| **Resource Usage** | ~50Mi per pod sidecar | ~100Mi for entire operator |
| **Kubernetes Native** | No (annotation-based) | Yes (CRD-based) |

### Architecture Comparison

```
AGENT INJECTOR                           VSO
===============                          ===

Per-Pod Pattern:                         Central Operator Pattern:

+------------------+                     +------------------+
| Pod              |                     | VSO Controller   |
|  +------------+  |                     |  (single pod)    |
|  | App        |  |                     +--------+---------+
|  +------------+  |                              |
|  +------------+  |                     watches CRDs
|  | Vault Agent|  | <-- sidecar                  |
|  | (sidecar)  |  |                              v
|  +------------+  |                     +------------------+
+------------------+                     | VaultStaticSecret|
       |                                 +--------+---------+
       v                                          |
+------------------+                     syncs secrets
| Vault            |                              |
+------------------+                              v
                                         +------------------+
Pod reads:                               | K8s Secret       |
/vault/secrets/config.txt                | (managed by VSO) |
                                         +--------+---------+
                                                  |
                                         consumed by
                                                  |
                                                  v
                                         +------------------+
                                         | Pod              |
                                         | (no sidecar)     |
                                         +------------------+

                                         Pod reads:
                                         - envFrom: secretRef
                                         - volumeMount: secret
```

---

## Architecture

### Lab Setup Architecture

```
+====================================================================================+
|                                    YOUR LAPTOP                                      |
+====================================================================================+
|                                                                                     |
|  +-----------------------------------------------------------------------------+   |
|  |                           MINIKUBE CLUSTER                                   |   |
|  +-----------------------------------------------------------------------------+   |
|  |                                                                              |   |
|  |  +---------------------------+     +----------------------------------+     |   |
|  |  | vault-secrets-operator NS |     | vault-test NS                     |     |   |
|  |  +---------------------------+     +----------------------------------+     |   |
|  |  |                           |     |                                  |     |   |
|  |  | VSO Controller            |     | VaultAuth (local)                |     |   |
|  |  | +---------------------+   |     | vault-auth                       |     |   |
|  |  | | vault-secrets-      |   |     | (uses vault-sa, test-role)       |     |   |
|  |  | | operator-controller |   |     |        |                         |     |   |
|  |  | | -manager            |   |     |        | used by                 |     |   |
|  |  | +----------+----------+   |     |        v                         |     |   |
|  |  |            |              |     | VaultStaticSecret                |     |   |
|  |  |            | uses         |     | myapp-config-sync                |     |   |
|  |  |            v              |     |        |                         |     |   |
|  |  | +---------------------+   |     |        | creates/updates         |     |   |
|  |  | | VaultConnection     |   |     |        v                         |     |   |
|  |  | | vault-connection    |<--+-----+ +------------------+             |     |   |
|  |  | +---------------------+   |     | | K8s Secret       |             |     |   |
|  |  |            |              |     | | myapp-config     |             |     |   |
|  |  | +---------------------+   |     | +--------+---------+             |     |   |
|  |  | | VaultAuth           |   |     |          |                       |     |   |
|  |  | | vault-auth          |   |     |          | consumed by           |     |   |
|  |  | | (operator SA)       |   |     |          v                       |     |   |
|  |  | +----------+----------+   |     | +------------------+             |     |   |
|  |  |            |              |     | | test-pod-vso     |             |     |   |
|  |  +------------|--------------|-----| | - env: username  |-------------+     |   |
|  |               |              |     | | - vol: /etc/     |                   |   |
|  +---------------|--------------|-----| |       secrets/   |-------------------+   |
|                  |              |     | +------------------+                       |
|  +---------------|--------------|-----+----------------------------------+---------+
|  |               |              |                                              |   |
|  +---------------|--------------|----------------------------------------------+   |
|                  |              |                                                   |
|  +---------------|--------------|--------------------------------------------------+
|  |               |     K8s auth with                                               |
|  |  ngrok tunnel |     vso-role JWT                                                |
|  |       ^       |              |                                                  |
|  |       |       |              |                                                  |
+--|-------|-------|--------------|--------------------------------------------------+
   |       |       |              |
   |       |       v              v
   |   +===|=======|==============|===================================+
   |   |   |       |    AWS       |    VAULT CLUSTER                  |
   |   +===|=======|==============|===================================+
   |       |       |              |                                   |
   |       |       |   +----------v-----------+                       |
   |       |       |   |  NLB:8200            |                       |
   |       |       |   +----------+-----------+                       |
   |       |       |              |                                   |
   |       |       |   +----------v-----------+                       |
   |       |       |   |  Vault HA Cluster    |                       |
   |       |       |   |  (3 nodes)           |                       |
   |       |       |   +----------+-----------+                       |
   |       |       |              |                                   |
   |       |       |   auth/kubernetes/       |                       |
   |       |       |   - vso-role             |                       |
   |       |       |   - test-role            |                       |
   |       |       |              |                                   |
   |       |       |   secret/myapp/config    |                       |
   |       |       |   - username             |                       |
   |       |       |   - password             |                       |
   |       |       |   - api_key              |                       |
   |       |       |              |                                   |
   |       |       +--------------|-----------------------------------+
   |       |                      |
   |       |   TokenReview API    |
   |       +<---------------------+
   |
   +-- K8s API validates JWT via ngrok
```

### Component Responsibilities

| Component | Location | Responsibility |
|-----------|----------|----------------|
| VSO Controller | vault-secrets-operator NS | Watches CRDs, syncs secrets |
| VaultConnection | vault-secrets-operator NS | Stores Vault address/TLS settings |
| VaultAuth | vault-secrets-operator NS | Authenticates VSO controller (operator SA) |
| VaultAuth | vault-test NS | Authenticates for secret sync (app SA) |
| VaultStaticSecret | vault-test NS | Defines secret to sync |
| K8s Secret | vault-test NS | Destination for synced secret |
| test-pod-vso | vault-test NS | Consumes K8s Secret |

---

## Authentication Flow

### 6-Step VSO Authentication Flow

```
+-------------------+
| 1. VSO Starts     |
+--------+----------+
         |
         v
+-------------------+
| 2. Reads          |
| VaultConnection   |
| - address         |
| - TLS settings    |
+--------+----------+
         |
         v
+-------------------+
| 3. Reads          |
| VaultAuth         |
| - method: k8s     |
| - role: vso-role  |
+--------+----------+
         |
         | Uses ServiceAccount JWT
         v
+-------------------+     +-----------------------+
| 4. Authenticates  |---->| Vault                 |
| to Vault          |     | POST /auth/k8s/login  |
+--------+----------+     +-----------+-----------+
         |                            |
         |                            | Validates JWT via
         |                            | TokenReview API
         |                            v
         |                +-----------------------+
         |                | K8s API (via ngrok)   |
         |                | TokenReview confirms  |
         |                | SA identity           |
         |                +-----------+-----------+
         |                            |
         |<---------------------------+
         | Receives Vault token
         v
+-------------------+
| 5. Reads          |
| VaultStaticSecret |
| - path: myapp/    |
|         config    |
| - destination:    |
|   myapp-config    |
+--------+----------+
         |
         | GET secret/data/myapp/config
         v
+-------------------+     +-----------------------+
| 6. Creates/Updates|---->| K8s Secret            |
| Kubernetes Secret |     | myapp-config          |
+-------------------+     | - username: testuser  |
                          | - password: ****      |
                          | - api_key: ****       |
                          +-----------------------+
```

### Detailed Steps

1. **VSO Controller Starts**
   - Deployed via Helm chart
   - Runs in `vault-secrets-operator` namespace
   - Watches for VaultConnection, VaultAuth, VaultStaticSecret CRDs

2. **VaultConnection Configuration**
   - VSO reads the VaultConnection CRD
   - Establishes connection parameters (address, TLS)
   - In this lab: `http://<NLB>:8200` with TLS verification disabled

3. **VaultAuth Configuration**
   - VSO reads the VaultAuth CRD
   - Determines auth method (Kubernetes) and role (`vso-role`)
   - Uses its own ServiceAccount (`vault-secrets-operator-controller-manager`)

4. **Vault Authentication**
   - VSO sends its ServiceAccount JWT to Vault's `/auth/kubernetes/login`
   - Vault validates the JWT via K8s TokenReview API (through ngrok tunnel)
   - K8s confirms: "This JWT belongs to ServiceAccount `vault-secrets-operator-controller-manager` in namespace `vault-secrets-operator`"
   - Vault checks role bindings and issues a token with attached policies

5. **Secret Sync Configuration**
   - VSO reads VaultStaticSecret CRD in `vault-test` namespace
   - Determines source path (`secret/myapp/config`) and destination (`myapp-config`)

6. **Secret Synchronization**
   - VSO fetches secret data from Vault using its token
   - Creates/updates the Kubernetes Secret with the fetched data
   - Adds labels and annotations for management

---

## CRD Hierarchy

VSO uses a hierarchy of Custom Resource Definitions:

```
VaultConnection (connection settings)
       |
       v
VaultAuth (authentication configuration)
       |
       v
VaultStaticSecret (secret sync definition)
       |
       v
Kubernetes Secret (created/managed)
```

### VaultConnection

Defines **how** to connect to Vault.

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: vault-secrets-operator  # Always in operator namespace
spec:
  address: http://vault-nlb.example.com:8200
  skipTLSVerify: true  # Lab only - use proper TLS in production
```

### VaultAuth

Defines **how** to authenticate to Vault.

**Pattern 1: Operator Namespace (for VSO controller)**

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: vault-secrets-operator
spec:
  vaultConnectionRef: vault-connection  # Same namespace reference
  method: kubernetes
  mount: kubernetes
  allowedNamespaces:
    - vault-test  # Allow vault-test to use this VaultAuth
  kubernetes:
    role: vso-role  # Vault role for operator
    serviceAccount: vault-secrets-operator-controller-manager
```

**Pattern 2: Application Namespace (for secret syncing)**

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: vault-test  # Same namespace as VaultStaticSecret
spec:
  vaultConnectionRef: vault-secrets-operator/vault-connection  # Cross-namespace
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: test-role  # Application's Vault role
    serviceAccount: vault-sa  # Application ServiceAccount
```

> **Note:** Using a local VaultAuth (Pattern 2) is recommended because VSO looks up the ServiceAccount in the same namespace as the VaultAuth. Cross-namespace VaultAuth references can cause ServiceAccount lookup issues.

### VaultStaticSecret

Defines **what** to sync.

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: myapp-config-sync
  namespace: vault-test
spec:
  vaultAuthRef: vault-auth  # Local namespace reference (recommended)
  # Or use cross-namespace: vault-secrets-operator/vault-auth
  type: kv-v2
  mount: secret
  path: myapp/config
  refreshAfter: 30s
  destination:
    name: myapp-config
    create: true
```

---

## Configuration Reference

### VaultConnection Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `address` | string | Yes | Vault server URL |
| `skipTLSVerify` | bool | No | Skip TLS certificate verification |
| `caCertSecretRef` | object | No | Reference to Secret containing CA cert |
| `tlsServerName` | string | No | TLS server name for verification |
| `timeout` | duration | No | Request timeout (default: 30s) |

### VaultAuth Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `vaultConnectionRef` | string | Yes | Name of VaultConnection |
| `method` | string | Yes | Auth method (kubernetes, jwt, appRole, etc.) |
| `mount` | string | Yes | Mount path in Vault |
| `kubernetes.role` | string | Yes* | Vault role for K8s auth |
| `kubernetes.serviceAccount` | string | Yes* | ServiceAccount to use |
| `kubernetes.audiences` | []string | No | Token audiences |

### VaultStaticSecret Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `vaultAuthRef` | string | Yes | namespace/name of VaultAuth |
| `type` | string | Yes | Secret engine type (kv-v1, kv-v2) |
| `mount` | string | Yes | Secrets engine mount path |
| `path` | string | Yes | Path to secret in Vault |
| `refreshAfter` | duration | No | Sync interval (default: 1m) |
| `destination.name` | string | Yes | K8s Secret name to create |
| `destination.create` | bool | No | Create if doesn't exist (default: true) |
| `destination.labels` | map | No | Labels to add to Secret |
| `destination.annotations` | map | No | Annotations to add |
| `rolloutRestartTargets` | []object | No | Workloads to restart on change |

---

## Secret Rotation

### Automatic Refresh

VSO automatically checks for secret changes based on `refreshAfter`:

```yaml
spec:
  refreshAfter: 30s  # Check every 30 seconds
```

When a change is detected:
1. VSO fetches the new secret value from Vault
2. Updates the Kubernetes Secret
3. Pods using `envFrom` require restart to see changes
4. Pods using `volumeMount` see changes automatically (kubelet refresh)

### Triggering Pod Restarts

Use `rolloutRestartTargets` to automatically restart workloads:

```yaml
spec:
  rolloutRestartTargets:
    - kind: Deployment
      name: myapp
    - kind: StatefulSet
      name: database
```

When the secret changes, VSO triggers a rollout restart of these workloads.

### Manual Refresh

Force a refresh by deleting the VaultStaticSecret status:

```bash
kubectl patch vaultstaticsecret myapp-config-sync -n vault-test \
  --type merge -p '{"status":null}'
```

---

## Troubleshooting

### Diagnostic Commands

```bash
# Check VSO controller status
kubectl get pods -n vault-secrets-operator
kubectl logs -l app.kubernetes.io/name=vault-secrets-operator -n vault-secrets-operator

# Check CRD statuses
kubectl get vaultconnection -n vault-secrets-operator
kubectl get vaultauth -n vault-secrets-operator
kubectl get vaultauth -n vault-test  # Local VaultAuth
kubectl get vaultstaticsecret -n vault-test

# Detailed status
kubectl describe vaultconnection vault-connection -n vault-secrets-operator
kubectl describe vaultauth vault-auth -n vault-secrets-operator
kubectl describe vaultauth vault-auth -n vault-test  # Local VaultAuth
kubectl describe vaultstaticsecret myapp-config-sync -n vault-test

# Check if K8s Secret was created
kubectl get secret myapp-config -n vault-test
kubectl get secret myapp-config -n vault-test -o yaml
```

### Common Issues

#### 1. VaultConnection Status: Not Valid

**Symptom:**
```
kubectl get vaultconnection vault-connection -n vault-secrets-operator
NAME               VALID   AGE
vault-connection   false   5m
```

**Causes:**
- Vault address is incorrect or unreachable
- TLS certificate issues

**Fix:**
```bash
# Check if Vault is reachable
curl -s $VAULT_ADDR/v1/sys/health

# Check VSO logs for connection errors
kubectl logs -l app.kubernetes.io/name=vault-secrets-operator -n vault-secrets-operator | grep -i error
```

#### 2. VaultAuth Status: Not Valid

**Symptom:**
```
kubectl get vaultauth vault-auth -n vault-secrets-operator
NAME         VALID   AGE
vault-auth   false   5m
```

**Causes:**
- Vault role doesn't exist
- ServiceAccount name mismatch
- TokenReview API not reachable (ngrok tunnel down)

**Fix:**
```bash
# Verify Vault role exists
vault read auth/kubernetes/role/vso-role

# Check if ServiceAccount name matches
kubectl get sa -n vault-secrets-operator

# Check ngrok tunnel is running
curl -s http://localhost:4040/api/tunnels

# Check VSO logs
kubectl logs -l app.kubernetes.io/name=vault-secrets-operator -n vault-secrets-operator | grep -i "permission denied\|unauthorized\|error"
```

#### 3. VaultStaticSecret Not Syncing

**Symptom:**
```
kubectl get secret myapp-config -n vault-test
Error from server (NotFound): secrets "myapp-config" not found
```

**Causes:**
- VaultAuth reference is wrong
- Secret path doesn't exist in Vault
- Policy doesn't allow reading the secret

**Fix:**
```bash
# Check VaultStaticSecret events
kubectl describe vaultstaticsecret myapp-config-sync -n vault-test

# Verify secret exists in Vault
vault kv get secret/myapp/config

# Check policy allows reading
vault policy read k8s-test-policy
```

#### 4. Pod Can't Read Secret

**Symptom:** Pod starts but environment variables are empty.

**Causes:**
- Secret doesn't exist yet (VSO hasn't synced)
- Wrong secret name in pod spec
- Pod created before secret

**Fix:**
```bash
# Verify secret exists
kubectl get secret myapp-config -n vault-test -o yaml

# Check secret has expected keys
kubectl get secret myapp-config -n vault-test -o jsonpath='{.data}' | jq

# Delete pod to recreate with secret
kubectl delete pod test-pod-vso -n vault-test
kubectl apply -f k8s-manifests/vso/test-pod-vso.yaml
```

### Decision Tree

```
Is VSO controller running?
├─ No → kubectl get pods -n vault-secrets-operator
│       → Check Helm installation
│       → helm list -n vault-secrets-operator
│
└─ Yes → Is VaultConnection valid?
         ├─ No → Check Vault address reachability
         │       → Check TLS settings
         │
         └─ Yes → Is VaultAuth valid?
                  ├─ No → Check Vault role exists
                  │       → Check ngrok tunnel
                  │       → Check ServiceAccount name
                  │
                  └─ Yes → Is K8s Secret created?
                           ├─ No → Check VaultStaticSecret events
                           │       → Check secret path in Vault
                           │       → Check policy permissions
                           │
                           └─ Yes → Can pod read secret?
                                    ├─ No → Check pod spec (secretRef name)
                                    │       → Restart pod
                                    │
                                    └─ Yes → Success!
```

---

## Quick Reference

### Deploy VSO

```bash
./scripts/07-deploy-vso.sh
```

### Test VSO

```bash
./scripts/08-test-vso.sh
```

### Verify Secret Sync

```bash
# Check K8s Secret
kubectl get secret myapp-config -n vault-test -o yaml

# Compare with Vault
vault kv get secret/myapp/config

# Check pod can read (note: env vars are lowercase)
kubectl exec test-pod-vso -n vault-test -- env | grep username
```

### Cleanup VSO Only

```bash
# Remove VSO manifests (includes both VaultAuth resources)
kubectl delete -f k8s-manifests/vso/

# Uninstall VSO Helm chart and namespace
helm uninstall vault-secrets-operator -n vault-secrets-operator
kubectl delete namespace vault-secrets-operator

# Delete vault-test namespace (includes local VaultAuth and synced secrets)
kubectl delete namespace vault-test

# Remove VSO role from Vault (optional - disabling auth removes all roles)
vault delete auth/kubernetes/role/vso-role
```

> **Note:** Deleting the `vault-test` namespace also removes the local VaultAuth and all synced K8s Secrets in that namespace.

---

## Official Resources

- [VSO Documentation](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [VSO Installation Guide](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/installation)
- [VSO Tutorial](https://developer.hashicorp.com/vault/tutorials/kubernetes-introduction/vault-secrets-operator)
- [K8s Integrations Comparison](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/comparisons)
- [VSO GitHub Repository](https://github.com/hashicorp/vault-secrets-operator)
