# Outputs for MongoDB Integration

output "mongodb_server_public_ip" {
  description = "Public IP address of the MongoDB server"
  value       = aws_instance.mongodb.public_ip
}

output "mongodb_server_private_ip" {
  description = "Private IP address of the MongoDB server"
  value       = aws_instance.mongodb.private_ip
}

output "mongodb_connection_string" {
  description = "MongoDB connection string (for direct access)"
  value       = "mongodb://vault_admin@${aws_instance.mongodb.private_ip}:27017/admin"
}

output "ssh_connection_command" {
  description = "SSH command to connect to the MongoDB server"
  value       = "ssh -i ${path.module}/mongodb-key.pem ec2-user@${aws_instance.mongodb.public_ip}"
}

output "ssh_private_key_file" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "vault_mount_path" {
  description = "Vault mount path for MongoDB database secrets engine"
  value       = var.configure_vault_db ? vault_mount.mongodb[0].path : "N/A"
}

output "vault_generate_readonly_creds" {
  description = "Vault command to generate readonly credentials"
  value       = "vault read ${var.vault_mount_path}/creds/readonly"
}

output "vault_generate_readwrite_creds" {
  description = "Vault command to generate readwrite credentials"
  value       = "vault read ${var.vault_mount_path}/creds/readwrite"
}

output "vault_generate_admin_creds" {
  description = "Vault command to generate admin credentials"
  value       = "vault read ${var.vault_mount_path}/creds/admin"
}

output "mongodb_admin_password" {
  description = "MongoDB admin password (for vault_admin user)"
  value       = random_password.mongodb_admin.result
  sensitive   = true
}

output "manual_test_1_connectivity" {
  description = "Test database connectivity (run from DB EC2 instance after SSH)"
  value       = "mongosh --eval 'db.version()'"
}

output "manual_test_2_vault_creds" {
  description = "Generate and test Vault dynamic credentials"
  value       = "vault read ${var.vault_mount_path}/creds/readonly"
}

output "database_info" {
  description = "Database connection information"
  value = {
    host     = aws_instance.mongodb.private_ip
    port     = 27017
    database = var.mongodb_db_name
    username = "vault_admin"
  }
}

output "pre_destroy_cleanup" {
  description = "Run before terraform destroy to avoid lease errors"
  value       = "vault lease revoke -prefix ${var.vault_mount_path}/"
}
