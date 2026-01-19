# Kubernetes Authentication Lab

This module sets up Vault Kubernetes authentication using a local Minikube cluster connected to your existing Vault cluster on AWS via an ngrok tunnel.

## Architecture

```
Your Laptop (Minikube)                         AWS (Vault Cluster)
+----------------------------------+          +------------------------+
|  Minikube Cluster                |          |  Vault (3-node HA)     |
|  +----------------------------+  |          |                        |
|  | vault-test namespace       |  |          |  NLB:8200 (public)     |
|  |  +----------------------+  |  |  HTTPS   |         ^              |
|  |  | test-pod (vault-sa)  |--+--+--------->|         |              |
|  |  +----------------------+  |  |          |         |              |
|  |  +----------------------+  |  |          |  Vault validates JWT   |
|  |  | Vault Agent Injector |  |  |          |  via TokenReview API   |
|  |  +----------------------+  |  |          |         |              |
|  +----------------------------+  |          +---------|-------------+
|           ^                      |                    |
|           | K8s API:8443         |                    |
|           v                      |                    |
|  +----------------------------+  |                    |
|  | ngrok tunnel               |<-+--------------------+
|  | https://xxxx.ngrok.io      |  |
|  +----------------------------+  |
+----------------------------------+
```

## Prerequisites

The setup scripts will verify these are installed:

| Tool | Purpose | Install (macOS) |
|------|---------|-----------------|
| minikube | Local Kubernetes cluster | `brew install minikube` |
| kubectl | Kubernetes CLI | `brew install kubectl` |
| helm | Package manager for K8s | `brew install helm` |
| ngrok | Tunnel to expose Minikube API | `brew install ngrok` |
| vault | Vault CLI | `brew install vault` |
| jq | JSON parsing in scripts | `brew install jq` |

**ngrok setup (one-time):**
```bash
# Sign up at https://ngrok.com (free account)
# Get your authtoken from dashboard
ngrok config add-authtoken <YOUR_AUTHTOKEN>
```

## Quick Start

### Step 1: Start local Minikube cluster
```bash
cd k8s-auth
./scripts/01-setup-minikube.sh
```

### Step 2: Start ngrok Tunnel so Vault (AWS) can reach Minikube API
```bash
./scripts/02-setup-ngrok.sh
# Note the KUBERNETES_HOST URL that is output
```

### Step 3: Configure Vault K8s auth method
```bash
export VAULT_ADDR="http://<your-vault-nlb>:8200"
export VAULT_TOKEN="<your-root-token>"
export KUBERNETES_HOST="https://<ngrok-url>"  # From step 2

./scripts/03-configure-vault-auth.sh
```

**What is KUBERNETES_HOST?**

`KUBERNETES_HOST` is the Kubernetes API server endpoint that Vault uses to validate pod JWTs via the TokenReview API.

In the auth flow:
1. Pod sends its ServiceAccount JWT to Vault
2. Vault calls `KUBERNETES_HOST` (the K8s API) to verify the JWT is valid
3. If valid, Vault issues a Vault token

Why export it?
- In this setup, Vault runs on AWS but needs to reach your local Minikube's API
- Since Minikube isn't publicly accessible, ngrok creates a tunnel exposing it
- You export `KUBERNETES_HOST=https://<ngrok-url>` so Vault knows where to validate tokens

Without it: Vault can't verify pod identities → authentication fails.

```
Pod JWT → Vault → calls KUBERNETES_HOST → K8s API validates → Vault issues token
```

**What is a Service Account?**

A Service Account is a Kubernetes identity for **pods**.

In the `03-configure-vault-auth.sh` script, there are two service accounts with different purpose:

| Service Account | Purpose |
|-----------------|---------|
| `vault-auth` | Vault uses this to call K8s TokenReview API to validate pod JWTs |
| `vault-sa` | The identity pods use when authenticating to Vault |

Think of it as:
- Humans use usernames/passwords
- Pods use ServiceAccounts + auto-mounted JWT tokens

The script creates a Vault role that says: *"Only pods running as `vault-sa` in namespace `vault-test` can authenticate."*

**Where are the Service Accounts created?**

| Service Account | Created In | Purpose |
|-----------------|------------|---------|
| `vault-auth` | `03-configure-vault-auth.sh` | Vault's credential to call K8s TokenReview API |
| `vault-sa` | `05-deploy-test-resources.sh` | Pod identity for authentication |

`vault-auth` is needed now (Step 3) because Vault needs it to validate tokens.

`vault-sa` is created later (Step 5) with the test pods because it's the application's identity.

**Why the separation?**

```
Step 3 (Vault config):     Creates vault-auth → Vault needs this NOW to validate tokens
Step 5 (Deploy pods):      Creates vault-sa   → Pods need this when they run
```

The Vault role in Step 3 just **declares** that `vault-sa` will be allowed - it doesn't need to exist yet. Kubernetes validates the SA exists only when pods actually try to use it.

### Step 4: Deploy Vault Agent Injector
```bash
./scripts/04-deploy-vault-agent.sh
```

### Step 5: Deploy Test pods
```bash
./scripts/05-deploy-test-resources.sh
```

### Step 6: Test Authentication
```bash
./scripts/test-k8s-auth.sh
```

### Step 7: Deploy Vault Secrets Operator (Optional)
```bash
./scripts/07-deploy-vso.sh
```

VSO provides an alternative to Agent Injector - it syncs Vault secrets to native Kubernetes Secrets.

### Step 8: Test VSO
```bash
./scripts/08-test-vso.sh
```

### Step 9: Inspect Certificates (Educational)
```bash
./scripts/06-inspect-certificates.sh
```

This optional script helps you understand the Kubernetes certificate chain:
- Includes mental models comparing production vs this lab's ngrok setup
- Inspects the K8s CA certificate, API server TLS certificate, and ngrok certificate
- Shows ServiceAccount JWT token structure
- Includes a command reference cheat sheet and troubleshooting tips

Run this anytime to learn about certificates or debug auth issues.

## Testing Manually

### Test from Pod (Manual Auth)

```bash
# Exec into the test pod
kubectl exec -it test-pod-manual -n vault-test -- /bin/sh

# Inside the pod, authenticate to Vault
vault write auth/kubernetes/login \
  role=test-role \
  jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

# Read a secret
vault kv get secret/myapp/config
```

### Test Vault Agent Injector

```bash
# Check injected secrets
kubectl exec test-pod-injector -n vault-test -c app -- \
  cat /vault/secrets/config.txt
```

### Test Vault Secrets Operator (VSO)

```bash
# Check VSO-synced K8s Secret
kubectl get secret myapp-config -n vault-test -o yaml

# Check pod reading secret via environment
kubectl exec test-pod-vso -n vault-test -- env | grep username

# Check pod reading secret via volume mount
kubectl exec test-pod-vso -n vault-test -- cat /etc/secrets/username
```

## Agent Injector vs VSO

| Aspect | Agent Injector | VSO |
|--------|---------------|-----|
| **Secret Delivery** | Ephemeral volume in pod | Native K8s Secret |
| **Architecture** | Sidecar per pod | Central operator |
| **Pod Awareness** | Needs Vault annotations | Standard K8s Secret consumption |
| **Resource Usage** | Higher (sidecar per pod) | Lower (single operator) |
| **K8s Native** | No (annotations) | Yes (CRDs) |
| **Templating** | Yes | Yes |
| **Use When** | Need advanced templating, broad auth | K8s-native patterns, shared secrets |

## File Structure

```
k8s-auth/
├── vault-policies/
│   └── k8s-test-policy.hcl          # Policy for test pods
├── scripts/
│   ├── 01-setup-minikube.sh         # Start minikube cluster
│   ├── 02-setup-ngrok.sh            # Start ngrok tunnel
│   ├── 03-configure-vault-auth.sh   # Configure Vault auth
│   ├── 04-deploy-vault-agent.sh     # Deploy injector via Helm
│   ├── 05-deploy-test-resources.sh  # Deploy test pods
│   ├── 06-inspect-certificates.sh   # Educational cert inspection
│   ├── 07-deploy-vso.sh             # Deploy Vault Secrets Operator
│   ├── 08-test-vso.sh               # Test VSO integration
│   ├── test-k8s-auth.sh             # Run test suite
│   └── cleanup.sh                   # Remove all resources
├── k8s-manifests/
│   ├── namespace.yaml               # vault-test namespace
│   ├── serviceaccount.yaml          # vault-sa ServiceAccount
│   ├── clusterrolebinding.yaml      # RBAC for SA
│   ├── test-pod-manual.yaml         # Pod for manual auth testing
│   ├── test-pod-injector.yaml       # Pod for injector testing
│   └── vso/                         # VSO Custom Resources
│       ├── vault-connection.yaml    # Connection to Vault
│       ├── vault-auth.yaml          # K8s auth (operator namespace)
│       ├── vault-auth-local.yaml    # K8s auth (vault-test namespace)
│       ├── vault-static-secret.yaml # Secret sync definition
│       └── test-pod-vso.yaml        # Pod consuming K8s Secret
├── docs/
│   ├── k8s-auth-flow.md             # Detailed auth flow explanation
│   ├── vault-agent-injector.md      # Injector guide
│   ├── vault-secrets-operator.md    # VSO guide
│   ├── troubleshooting.md           # Lab-specific issues (Minikube + ngrok)
│   └── k8s-auth-troubleshooting-general.md  # General K8s auth issues
└── README.md                        # This file
```

## Cleanup

```bash
# Remove Vault auth config and K8s resources
./scripts/cleanup.sh

# Stop Minikube
minikube stop

# Fully delete Minikube (optional)
minikube delete
```

The Vault cluster on AWS remains intact.

## Troubleshooting

- **Lab issues (Minikube + ngrok):** [docs/troubleshooting.md](docs/troubleshooting.md)
- **General K8s auth issues (any environment):** [docs/k8s-auth-troubleshooting-general.md](docs/k8s-auth-troubleshooting-general.md)

### Quick Checks

```bash
# Is Minikube running?
minikube status

# Is ngrok tunnel active?
curl -s http://localhost:4040/api/tunnels | jq '.tunnels[0].public_url'

# Is Kubernetes auth enabled?
vault auth list | grep kubernetes

# Can pod authenticate?
kubectl exec test-pod-manual -n vault-test -- \
  vault write auth/kubernetes/login \
    role=test-role \
    jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

## Documentation

- [Kubernetes Auth Flow](docs/k8s-auth-flow.md) - Detailed explanation of the authentication process
- [Vault Agent Injector](docs/vault-agent-injector.md) - Guide to automatic secret injection
- [Vault Secrets Operator](docs/vault-secrets-operator.md) - Guide to VSO and K8s-native secrets
- [Troubleshooting (Lab)](docs/troubleshooting.md) - Minikube + ngrok specific issues
- [Troubleshooting (General)](docs/k8s-auth-troubleshooting-general.md) - Universal K8s auth issues for any environment

## Official Documentation

- [Vault Kubernetes Auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [Vault Kubernetes Auth API](https://developer.hashicorp.com/vault/api-docs/auth/kubernetes)
- [Vault Agent Injector](https://developer.hashicorp.com/vault/docs/platform/k8s/injector)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [K8s Integrations Comparison](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/comparisons)
