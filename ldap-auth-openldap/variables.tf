variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "vaultlab"
}

variable "vpc_id" {
  description = "VPC ID where LDAP server will be deployed (use VPC from awskms-autounseal)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the LDAP server (optional - will use first available if not specified)"
  type        = string
  default     = ""
}

variable "vault_addr" {
  description = "VAULT_ADDR of the existing Vault cluster (e.g., http://nlb-dns:8200)"
  type        = string
}

variable "vault_token" {
  description = "Vault token with permissions to configure auth methods"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type for OpenLDAP server"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ldap_cidrs" {
  description = "CIDR blocks allowed for LDAP access (default: VPC CIDR)"
  type        = list(string)
  default     = []
}

variable "ldap_domain" {
  description = "LDAP domain (e.g., vaultlab.local becomes dc=vaultlab,dc=local)"
  type        = string
  default     = "vaultlab.local"
}

variable "ldap_admin_password" {
  description = "Password for LDAP admin user"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "ldap_test_user_password" {
  description = "Password for test LDAP users (alice, bob, charlie)"
  type        = string
  sensitive   = true
  default     = "password123"
}

variable "configure_vault_ldap" {
  description = "Whether to automatically configure Vault LDAP auth method"
  type        = bool
  default     = true
}
