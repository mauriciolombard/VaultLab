variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "ldaplab"
}

variable "vault_version" {
  description = "Version of Vault to install"
  type        = string
  default     = "1.20.2+ent"
}

variable "vault_license" {
  description = "Vault Enterprise license string"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type for Vault and LDAP nodes"
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_vault_cidrs" {
  description = "CIDR blocks allowed for Vault API access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ldap_admin_password" {
  description = "Admin password for OpenLDAP"
  type        = string
  default     = "admin123"
  sensitive   = true
}

variable "ldap_domain" {
  description = "LDAP domain (e.g., example.com becomes dc=example,dc=com)"
  type        = string
  default     = "vaultlab.local"
}

variable "ldap_organisation" {
  description = "LDAP organisation name"
  type        = string
  default     = "VaultLab"
}

variable "enable_ldap_tls" {
  description = "Enable TLS on OpenLDAP (true=LDAPS on 636, false=plaintext on 389)"
  type        = bool
  default     = false
}
