# Troubleshooting Guide - Vault Kubernetes Auth (Lab-Specific)

This guide covers issues specific to this **lab setup** (Minikube + ngrok).

> **For production/general troubleshooting**, see [k8s-auth-troubleshooting-general.md](k8s-auth-troubleshooting-general.md) which covers universal K8s auth issues for any environment (EKS, GKE, AKS, self-hosted).

## Quick Diagnostic Commands

```bash
# Check all components
minikube status                              # Minikube running?
kubectl cluster-info                         # K8s API accessible?
curl -s http://localhost:4040/api/tunnels    # ngrok tunnel active?
vault status                                 # Vault accessible?
vault auth list | grep kubernetes            # K8s auth enabled?

# Check test resources
kubectl get pods -n vault-test               # Test pods running?
kubectl get pods -n vault                    # Injector running?
```

## Common Issues

### 1. ngrok Tunnel Issues

#### Problem: "Could not get ngrok tunnel URL"

**Symptoms:**
- `02-setup-ngrok.sh` fails
- No URL output from ngrok

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| ngrok not authenticated | Run `ngrok config add-authtoken <TOKEN>` |
| Port already in use | Kill existing ngrok: `pkill ngrok` |
| API not responding | Check http://localhost:4040 in browser |

**Debug:**
```bash
# Check ngrok logs
cat /tmp/ngrok.log

# Check if ngrok is running
ps aux | grep ngrok

# Try starting ngrok manually
ngrok tcp $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed 's|https://||')
```

#### Problem: ngrok URL changed

**Symptoms:**
- Vault auth suddenly fails
- "connection refused" errors from Vault

**Solution:**
```bash
# Get new URL
NEW_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' | sed 's|tcp://|https://|')
echo "New URL: $NEW_URL"

# Update Vault config
vault write auth/kubernetes/config \
  kubernetes_host="$NEW_URL" \
  token_reviewer_jwt="$(kubectl get secret vault-auth-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)" \
  disable_iss_validation=true \
  disable_local_ca_jwt=true
```

### 2. Vault Authentication Failures

#### Problem: "permission denied" on login

**Symptoms:**
```
Error writing data to auth/kubernetes/login: Error making API request.
Code: 403. Errors:
* permission denied
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Wrong role name | Verify role exists: `vault list auth/kubernetes/role` |
| Wrong ServiceAccount | Check SA name matches role binding |
| Wrong namespace | Check namespace matches role binding |
| Role doesn't exist | Create role: `vault read auth/kubernetes/role/test-role` |

**Debug:**
```bash
# Check what role expects
vault read auth/kubernetes/role/test-role

# Check pod's ServiceAccount
kubectl get pod test-pod-manual -n vault-test -o jsonpath='{.spec.serviceAccountName}'

# Check pod's namespace
kubectl get pod test-pod-manual -n vault-test -o jsonpath='{.metadata.namespace}'
```

#### Problem: "service account not found"

**Symptoms:**
```
* service account name not authorized
```

**Solution:**
```bash
# List ServiceAccounts
kubectl get serviceaccounts -n vault-test

# Verify vault-sa exists
kubectl get serviceaccount vault-sa -n vault-test

# Check role binding
vault read auth/kubernetes/role/test-role | grep bound_service_account
```

#### Problem: "invalid JWT" or token validation failed

**Symptoms:**
```
* error validating token: invalid JWT
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Token expired | Tokens are short-lived, retry |
| Wrong K8s host | Check ngrok URL is current |
| TokenReview failed | Check vault-auth SA permissions |
| Network issue | Verify Vault can reach ngrok URL |

**Debug:**
```bash
# Check token from pod
kubectl exec test-pod-manual -n vault-test -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq .

# Test TokenReview manually from Vault server
# (requires access to Vault server)
```

### 3. Kubernetes Issues

#### Problem: Minikube won't start

**Solutions:**
```bash
# Clean start
minikube delete
minikube start --driver=docker

# Check Docker is running
docker ps

# Try different driver
minikube start --driver=hyperkit  # macOS
minikube start --driver=virtualbox
```

#### Problem: kubectl can't connect

**Solutions:**
```bash
# Reset kubeconfig
minikube update-context

# Check config
kubectl config view

# Verify minikube is running
minikube status
```

#### Problem: Test pods not starting

**Debug:**
```bash
# Check pod status
kubectl get pods -n vault-test
kubectl describe pod test-pod-manual -n vault-test

# Check events
kubectl get events -n vault-test --sort-by='.lastTimestamp'

# Check logs
kubectl logs test-pod-manual -n vault-test
```

### 4. Vault Agent Injector Issues

#### Problem: Secrets not being injected

**Symptoms:**
- `/vault/secrets/` directory is empty
- Pod is running but no secrets

**Debug:**
```bash
# Check injector is running
kubectl get pods -n vault -l app.kubernetes.io/name=vault-agent-injector

# Check webhook is registered
kubectl get mutatingwebhookconfiguration | grep vault

# Check pod has vault containers
kubectl get pod test-pod-injector -n vault-test -o jsonpath='{.spec.containers[*].name}'

# Check init container logs
kubectl logs test-pod-injector -n vault-test -c vault-agent-init

# Check sidecar logs
kubectl logs test-pod-injector -n vault-test -c vault-agent
```

#### Problem: Init container stuck

**Symptoms:**
- Pod stuck in "Init:0/1" state
- Init container not completing

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Can't reach Vault | Check VAULT_ADDR is correct |
| Auth failed | Check role and SA configuration |
| Secret path wrong | Verify secret exists in Vault |

**Debug:**
```bash
# Check init container logs
kubectl logs test-pod-injector -n vault-test -c vault-agent-init

# Describe pod for events
kubectl describe pod test-pod-injector -n vault-test
```

#### Problem: Webhook not firing

**Symptoms:**
- No vault-agent containers added to pods
- Annotations seem ignored

**Solutions:**
```bash
# Check webhook configuration
kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg -o yaml

# Check injector logs
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector

# Verify pod has correct annotations
kubectl get pod test-pod-injector -n vault-test -o jsonpath='{.metadata.annotations}'
```

### 5. Network Connectivity Issues

#### Problem: Pod can't reach Vault

**Symptoms:**
```
Error making API request: dial tcp: lookup vault-nlb...: no such host
```

**Solutions:**
```bash
# Test from pod
kubectl exec test-pod-manual -n vault-test -- \
  wget -q -O- http://<VAULT_NLB>:8200/v1/sys/health

# Check DNS resolution
kubectl exec test-pod-manual -n vault-test -- \
  nslookup <VAULT_NLB_DNS>

# Check if NLB is publicly accessible
curl http://<VAULT_NLB>:8200/v1/sys/health
```

#### Problem: Vault can't reach Kubernetes API (via ngrok)

**Debug:**
```bash
# Check ngrok tunnel is active
curl -s http://localhost:4040/api/tunnels | jq '.tunnels[0].public_url'

# Test connectivity to ngrok URL
curl -k https://<ngrok-url>/healthz

# Check from Vault server logs (if accessible)
```

---

## Kubernetes CLI Quick Reference

Common kubectl commands for troubleshooting and learning.

### Pod Lifecycle

```bash
# Recreate a pod (pick up config/secret changes)
kubectl delete pod <pod-name> -n <namespace>
kubectl apply -f <manifest.yaml>

# View pod startup logs
kubectl logs <pod-name> -n <namespace>

# Follow logs in real-time
kubectl logs -f <pod-name> -n <namespace>

# Logs from specific container (multi-container pods)
kubectl logs <pod-name> -n <namespace> -c <container-name>

# Previous container logs (after crash)
kubectl logs <pod-name> -n <namespace> --previous
```

### Inspecting Resources

```bash
# Get resource status
kubectl get pods -n <namespace>
kubectl get secrets -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Detailed resource info
kubectl describe pod <pod-name> -n <namespace>
kubectl describe secret <secret-name> -n <namespace>

# Full YAML output
kubectl get pod <pod-name> -n <namespace> -o yaml
```

### Secrets

```bash
# List secret keys
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data}' | jq 'keys'

# Decode a secret value
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d

# View all decoded values
kubectl get secret <secret-name> -n <namespace> -o json | jq '.data | map_values(@base64d)'
```

### Exec & Debug

```bash
# Run command in pod
kubectl exec <pod-name> -n <namespace> -- <command>

# Interactive shell
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Check environment variables
kubectl exec <pod-name> -n <namespace> -- env | grep -i <pattern>

# Check mounted files
kubectl exec <pod-name> -n <namespace> -- ls -la /path/to/mount
kubectl exec <pod-name> -n <namespace> -- cat /path/to/file
```

### Watching Resources

```bash
# Watch pods in real-time
kubectl get pods -n <namespace> -w

# Watch with timestamps
kubectl get pods -n <namespace> -w --output-watch-events

# Watch specific resource
kubectl get secret <secret-name> -n <namespace> -w
```

### ServiceAccounts & RBAC

```bash
# List ServiceAccounts
kubectl get serviceaccounts -n <namespace>

# Check pod's ServiceAccount
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'

# View ClusterRoleBindings
kubectl get clusterrolebindings | grep <pattern>
kubectl describe clusterrolebinding <name>
```

---

## Reset Procedures

### Full Reset

```bash
# Stop everything
./scripts/cleanup.sh
minikube stop
pkill ngrok

# Start fresh
minikube delete
./scripts/01-setup-minikube.sh
./scripts/02-setup-ngrok.sh
# ... continue with remaining scripts
```

### Reset Vault Auth Only

```bash
# Disable and re-enable kubernetes auth
vault auth disable kubernetes
vault auth enable kubernetes

# Reconfigure
./scripts/03-configure-vault-auth.sh
```

### Reset Kubernetes Resources Only

```bash
# Delete test namespace
kubectl delete namespace vault-test

# Recreate
./scripts/05-deploy-test-resources.sh
```

## Logs to Collect for Support

When asking for help, collect these logs:

```bash
# Environment info
minikube version
kubectl version
vault version
ngrok version

# Minikube status
minikube status

# Vault status
vault status
vault auth list

# Kubernetes auth config
vault read auth/kubernetes/config
vault read auth/kubernetes/role/test-role

# Pod status
kubectl get pods -A
kubectl describe pod test-pod-manual -n vault-test

# ngrok status
curl -s http://localhost:4040/api/tunnels | jq .

# Injector logs (if using)
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector --tail=100
```

## Getting Help

1. **Check this guide** - Most common issues are covered above
2. **Check official docs** - https://developer.hashicorp.com/vault/docs/auth/kubernetes
3. **Vault community** - https://discuss.hashicorp.com/c/vault
4. **GitHub issues** - https://github.com/hashicorp/vault/issues
