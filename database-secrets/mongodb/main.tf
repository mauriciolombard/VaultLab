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
    null = {
      source  = "hashicorp/null"
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
      Component   = "database-secrets-mongodb"
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

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Reference existing VPC (from awskms-autounseal)
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

# SSH Key Pair for MongoDB server
resource "tls_private_key" "mongodb" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "mongodb" {
  key_name   = "${var.cluster_name}-mongodb-key"
  public_key = tls_private_key.mongodb.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.mongodb.private_key_pem
  filename        = "${path.module}/mongodb-key.pem"
  file_permission = "0600"
}

# Generate random password for MongoDB admin user
resource "random_password" "mongodb_admin" {
  length  = 24
  special = false
}
