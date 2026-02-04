# Vault Database Secrets Engine Configuration for MySQL

# Mount the database secrets engine
resource "vault_mount" "mysql" {
  count = var.configure_vault_db ? 1 : 0

  path        = var.vault_mount_path
  type        = "database"
  description = "Database secrets engine for MySQL"

  default_lease_ttl_seconds = var.default_ttl
  max_lease_ttl_seconds     = var.max_ttl
}

# Configure the MySQL connection
resource "vault_database_secret_backend_connection" "mysql" {
  count = var.configure_vault_db ? 1 : 0

  backend       = vault_mount.mysql[0].path
  name          = "mysql"
  allowed_roles = ["readonly", "readwrite", "admin"]

  mysql {
    connection_url = "{{username}}:{{password}}@tcp(${aws_instance.mysql.private_ip}:3306)/${var.mysql_db_name}"
    username       = "vault_admin"
    password       = random_password.mysql_root.result
  }

  depends_on = [null_resource.mysql_ready]
}

# Lease cleanup resource - ensures all leases are revoked BEFORE the connection is destroyed
# This prevents "failed to find entry for connection" errors during terraform destroy
resource "terraform_data" "lease_cleanup" {
  count = var.configure_vault_db ? 1 : 0

  # Capture the mount path at creation time (available during destroy via self.output)
  input = vault_mount.mysql[0].path

  # Must be created after the connection exists
  depends_on = [vault_database_secret_backend_connection.mysql]

  provisioner "local-exec" {
    when       = destroy
    command    = "vault lease revoke -prefix ${self.output}/ 2>/dev/null || true"
    on_failure = continue
  }
}

# Readonly role - SELECT only
resource "vault_database_secret_backend_role" "readonly" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.mysql[0].path
  name        = "readonly"
  db_name     = vault_database_secret_backend_connection.mysql[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';",
    "GRANT SELECT ON ${var.mysql_db_name}.* TO '{{name}}'@'%';"
  ]

  revocation_statements = [
    "DROP USER IF EXISTS '{{name}}'@'%';"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}

# Readwrite role - SELECT, INSERT, UPDATE, DELETE
resource "vault_database_secret_backend_role" "readwrite" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.mysql[0].path
  name        = "readwrite"
  db_name     = vault_database_secret_backend_connection.mysql[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';",
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ${var.mysql_db_name}.* TO '{{name}}'@'%';"
  ]

  revocation_statements = [
    "DROP USER IF EXISTS '{{name}}'@'%';"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}

# Admin role - Full privileges
resource "vault_database_secret_backend_role" "admin" {
  count = var.configure_vault_db ? 1 : 0

  backend     = vault_mount.mysql[0].path
  name        = "admin"
  db_name     = vault_database_secret_backend_connection.mysql[0].name
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  creation_statements = [
    "CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';",
    "GRANT ALL PRIVILEGES ON ${var.mysql_db_name}.* TO '{{name}}'@'%';",
    "GRANT CREATE USER ON *.* TO '{{name}}'@'%';",
    "GRANT SELECT ON mysql.* TO '{{name}}'@'%';"
  ]

  revocation_statements = [
    "DROP USER IF EXISTS '{{name}}'@'%';"
  ]

  # Ensures roles are destroyed before lease cleanup runs
  depends_on = [terraform_data.lease_cleanup]
}
