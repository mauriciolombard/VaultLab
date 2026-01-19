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
  description = "VPC ID where AD server will be deployed (use VPC from awskms-autounseal)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the AD server (optional - will use first available if not specified)"
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
  description = "EC2 instance type for Windows AD server (t3.medium minimum recommended)"
  type        = string
  default     = "t3.medium"
}

variable "allowed_rdp_cidrs" {
  description = "CIDR blocks allowed for RDP access (port 3389)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ldap_cidrs" {
  description = "CIDR blocks allowed for LDAP access (default: VPC CIDR)"
  type        = list(string)
  default     = []
}

variable "ad_domain_name" {
  description = "Active Directory domain name (e.g., vaultlab.local)"
  type        = string
  default     = "vaultlab.local"
}

variable "ad_netbios_name" {
  description = "NetBIOS name for the AD domain (max 15 chars)"
  type        = string
  default     = "VAULTLAB"
}

variable "ad_safe_mode_password" {
  description = "AD Directory Services Restore Mode (DSRM) password"
  type        = string
  sensitive   = true
  default     = "SafeMode123!"
}

variable "windows_admin_password" {
  description = "Windows Administrator password (leave empty to auto-generate)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ad_admin_password" {
  description = "Password for AD service account (used by Vault for LDAP bind)"
  type        = string
  sensitive   = true
  default     = "VaultBind123!"
}

variable "ad_test_user_password" {
  description = "Password for test AD users (alice, bob, charlie)"
  type        = string
  sensitive   = true
  default     = "Password123!"
}

variable "configure_vault_ldap" {
  description = "Whether to automatically configure Vault LDAP auth method"
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 50
}
