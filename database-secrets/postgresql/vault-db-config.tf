# Vault Database Secrets Engine Configuration for PostgreSQL

# Mount the database secrets engine
resource "vault_mount" "postgresql" {
  count = var.configure_vault_db ? 1 : 0

  path        = var.vault_mount_path
  type        = "database"
  description = "Database secrets engine for PostgreSQL"

  default_lease_ttl_seconds = var.default_ttl
  max_lease_ttl_seconds     = var.max_ttl
}

# Configure the PostgreSQL connection
resource "vault_database_secret_backend_connection" "postgresql" {
  count = var.configure_vault_db ? 1 : 0

  backend       = vault_mount.postgresql[0].path
  name          = "postgresql"
  allowed_roles = ["readonly", "readwrite", "admin"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${aws_instance.postgresql.private_ip}:5432/${var.postgres_db_name}?sslmode=disable"
    username       = "vault_admin"
    password       = random_password.postgres_admin.result
  }

  depends_on = [aws_instance.postgresql]
}

# Lease cleanup resource - ensures all leases are revoked BEFORE the connection is destroyed
# This prevents "failed to find entry for connection" errors during terraform destroy
resource "terraform_data" "lease_cleanup" {
  count = var.configure_vault_db ? 1 : 0

  # Capture the mount path at creation time (available during destroy via self.output)
  input = vault_mount.postgresql[0].path

  # Must be created after the connection exists
  depends_on = [vault_database_secret_backend_connection.postgresql]

  provisioner "local-exec" {
    when       = destroy
    command    = "vault lease revoke -prefix ${self.output}/ 2>/dev/null || true"
    on_failure = continue
  }
}

# Readonly role - SELECT only
resource "vault_database_secret_backend_role" "readonly" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.postgresql[0].path
  name        = "readonly"
  db_name     = vault_database_secret_backend_connection.postgresql[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO \"{{name}}\";"
  ]

  revocation_statements = [
    "REASSIGN OWNED BY \"{{name}}\" TO vault_admin;",
    "DROP OWNED BY \"{{name}}\";",
    "DROP ROLE IF EXISTS \"{{name}}\";"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}

# Readwrite role - SELECT, INSERT, UPDATE, DELETE
resource "vault_database_secret_backend_role" "readwrite" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.postgresql[0].path
  name        = "readwrite"
  db_name     = vault_database_secret_backend_connection.postgresql[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
    "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"{{name}}\";"
  ]

  revocation_statements = [
    "REASSIGN OWNED BY \"{{name}}\" TO vault_admin;",
    "DROP OWNED BY \"{{name}}\";",
    "DROP ROLE IF EXISTS \"{{name}}\";"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}

# Admin role - Full privileges
resource "vault_database_secret_backend_role" "admin" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.postgresql[0].path
  name        = "admin"
  db_name     = vault_database_secret_backend_connection.postgresql[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' CREATEROLE CREATEDB;",
    "GRANT ALL PRIVILEGES ON DATABASE ${var.postgres_db_name} TO \"{{name}}\";",
    "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
    "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"{{name}}\";"
  ]

  revocation_statements = [
    "REASSIGN OWNED BY \"{{name}}\" TO vault_admin;",
    "DROP OWNED BY \"{{name}}\";",
    "DROP ROLE IF EXISTS \"{{name}}\";"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}
