# Vault Database Secrets Engine Configuration for MongoDB

# Mount the database secrets engine
resource "vault_mount" "mongodb" {
  count = var.configure_vault_db ? 1 : 0

  path        = var.vault_mount_path
  type        = "database"
  description = "Database secrets engine for MongoDB"

  default_lease_ttl_seconds = var.default_ttl
  max_lease_ttl_seconds     = var.max_ttl
}

# Configure the MongoDB connection
resource "vault_database_secret_backend_connection" "mongodb" {
  count = var.configure_vault_db ? 1 : 0

  backend       = vault_mount.mongodb[0].path
  name          = "mongodb"
  allowed_roles = ["readonly", "readwrite", "admin"]

  mongodb {
    connection_url = "mongodb://{{username}}:{{password}}@${aws_instance.mongodb.private_ip}:27017/admin"
    username       = "vault_admin"
    password       = random_password.mongodb_admin.result
  }

  depends_on = [null_resource.mongodb_ready]
}

# Lease cleanup resource - ensures all leases are revoked BEFORE the connection is destroyed
# This prevents "failed to find entry for connection" errors during terraform destroy
resource "terraform_data" "lease_cleanup" {
  count = var.configure_vault_db ? 1 : 0

  # Capture the mount path at creation time (available during destroy via self.output)
  input = vault_mount.mongodb[0].path

  # Must be created after the connection exists
  depends_on = [vault_database_secret_backend_connection.mongodb]

  provisioner "local-exec" {
    when       = destroy
    command    = "vault lease revoke -prefix ${self.output}/ 2>/dev/null || true"
    on_failure = continue
  }
}

# Readonly role - read operations only
resource "vault_database_secret_backend_role" "readonly" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.mongodb[0].path
  name        = "readonly"
  db_name     = vault_database_secret_backend_connection.mongodb[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "{\"db\": \"${var.mongodb_db_name}\", \"roles\": [{\"role\": \"read\", \"db\": \"${var.mongodb_db_name}\"}]}"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}

# Readwrite role - read and write operations
resource "vault_database_secret_backend_role" "readwrite" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.mongodb[0].path
  name        = "readwrite"
  db_name     = vault_database_secret_backend_connection.mongodb[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "{\"db\": \"${var.mongodb_db_name}\", \"roles\": [{\"role\": \"readWrite\", \"db\": \"${var.mongodb_db_name}\"}]}"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}

# Admin role - database admin operations
resource "vault_database_secret_backend_role" "admin" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.mongodb[0].path
  name        = "admin"
  db_name     = vault_database_secret_backend_connection.mongodb[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "{\"db\": \"admin\", \"roles\": [{\"role\": \"dbAdminAnyDatabase\", \"db\": \"admin\"}, {\"role\": \"readWriteAnyDatabase\", \"db\": \"admin\"}]}"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}
