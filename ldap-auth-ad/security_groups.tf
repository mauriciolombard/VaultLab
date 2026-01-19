# Security Groups for Windows Active Directory Server

resource "aws_security_group" "ad" {
  name        = "${var.cluster_name}-ad-sg"
  description = "Security group for Windows Active Directory server"
  vpc_id      = data.aws_vpc.selected.id

  # RDP access
  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.allowed_rdp_cidrs
  }

  # WinRM (Windows Remote Management)
  ingress {
    description = "WinRM HTTP"
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = var.allowed_rdp_cidrs
  }

  ingress {
    description = "WinRM HTTPS"
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = var.allowed_rdp_cidrs
  }

  # LDAP (Active Directory)
  ingress {
    description = "LDAP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "LDAP UDP"
    from_port   = 389
    to_port     = 389
    protocol    = "udp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  # LDAPS (LDAP over SSL)
  ingress {
    description = "LDAPS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  # Global Catalog
  ingress {
    description = "Global Catalog"
    from_port   = 3268
    to_port     = 3268
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "Global Catalog SSL"
    from_port   = 3269
    to_port     = 3269
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  # Kerberos
  ingress {
    description = "Kerberos"
    from_port   = 88
    to_port     = 88
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "Kerberos UDP"
    from_port   = 88
    to_port     = 88
    protocol    = "udp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  # DNS
  ingress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  # SMB/CIFS (for Group Policy, etc.)
  ingress {
    description = "SMB"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-ad-sg"
  }
}
