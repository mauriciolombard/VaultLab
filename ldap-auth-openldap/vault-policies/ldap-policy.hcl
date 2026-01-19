# Vault Policy for LDAP Admins (vault-admins group)
# This policy grants elevated privileges for Vault administration

# Full access to secrets engine
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list", "delete"]
}

# Manage auth methods (useful for troubleshooting)
path "auth/*" {
  capabilities = ["read", "list"]
}

path "sys/auth" {
  capabilities = ["read"]
}

# Read system health and status
path "sys/health" {
  capabilities = ["read"]
}

path "sys/leader" {
  capabilities = ["read"]
}

# List available secrets engines
path "sys/mounts" {
  capabilities = ["read"]
}

# Read own token info
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# Read policies (for troubleshooting)
path "sys/policies/acl/*" {
  capabilities = ["read", "list"]
}

# Identity information
path "identity/*" {
  capabilities = ["read", "list"]
}
