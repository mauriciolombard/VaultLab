terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "VaultLab"
      Environment = "lab"
      Component   = "ldap-auth-ad"
      ManagedBy   = "terraform"
    }
  }
}

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Windows Server 2022 AMI
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Reference existing VPC (from awskms-autounseal or user-provided)
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Get subnets from the VPC
data "aws_subnets" "available" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

# Generate random password for Windows Administrator if not provided
resource "random_password" "windows_admin" {
  count   = var.windows_admin_password == "" ? 1 : 0
  length  = 16
  special = true
  override_special = "!@#$%"
}

locals {
  windows_admin_password = var.windows_admin_password != "" ? var.windows_admin_password : random_password.windows_admin[0].result
}

# SSH Key Pair for AD server (used for RDP key retrieval)
resource "tls_private_key" "ad" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ad" {
  key_name   = "${var.cluster_name}-ad-key"
  public_key = tls_private_key.ad.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ad.private_key_pem
  filename        = "${path.module}/ad-key.pem"
  file_permission = "0600"
}
