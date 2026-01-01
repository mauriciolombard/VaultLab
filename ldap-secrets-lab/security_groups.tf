# Security Group for Vault Instance
resource "aws_security_group" "vault" {
  name        = "${var.cluster_name}-vault-sg"
  description = "Security group for Vault node"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Vault API
  ingress {
    description = "Vault API"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = var.allowed_vault_cidrs
  }

  # Vault Cluster (for future expansion)
  ingress {
    description = "Vault Cluster"
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    self        = true
  }

  # All outbound traffic
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-vault-sg"
  }
}

# Security Group for OpenLDAP Instance
resource "aws_security_group" "ldap" {
  name        = "${var.cluster_name}-ldap-sg"
  description = "Security group for OpenLDAP server"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # LDAP plaintext (389)
  ingress {
    description = "LDAP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # LDAP plaintext from Vault SG
  ingress {
    description     = "LDAP from Vault"
    from_port       = 389
    to_port         = 389
    protocol        = "tcp"
    security_groups = [aws_security_group.vault.id]
  }

  # LDAPS (636)
  ingress {
    description = "LDAPS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # LDAPS from Vault SG
  ingress {
    description     = "LDAPS from Vault"
    from_port       = 636
    to_port         = 636
    protocol        = "tcp"
    security_groups = [aws_security_group.vault.id]
  }

  # phpLDAPadmin web UI
  ingress {
    description = "phpLDAPadmin"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # All outbound traffic
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-ldap-sg"
  }
}
