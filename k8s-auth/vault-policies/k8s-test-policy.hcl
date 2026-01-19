# Vault Policy for Kubernetes-authenticated pods
# This policy grants access to test secrets for pods authenticating via the kubernetes auth method

# Allow reading secrets from the KV v2 secrets engine at secret/
# Note: KV v2 uses secret/data/* path for reading
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/myapp/*" {
  capabilities = ["read", "list"]
}

# Allow reading from KV v1 style path (if using KV v1)
path "secret/myapp/*" {
  capabilities = ["read", "list"]
}

# Allow pods to look up their own token info
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow pods to renew their own token
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow reading Kubernetes auth config (for troubleshooting)
path "auth/kubernetes/config" {
  capabilities = ["read"]
}

# Allow listing roles (for troubleshooting)
path "auth/kubernetes/role/*" {
  capabilities = ["read", "list"]
}

# System health endpoint (useful for health checks)
path "sys/health" {
  capabilities = ["read"]
}
