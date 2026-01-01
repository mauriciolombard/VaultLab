# IAM Role for Vault EC2 Instance
resource "aws_iam_role" "vault" {
  name = "${var.cluster_name}-vault-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-vault-role"
  }
}

# IAM Policy for KMS Access
resource "aws_iam_role_policy" "vault_kms" {
  name = "${var.cluster_name}-vault-kms-policy"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.vault_unseal.arn
      }
    ]
  })
}

# Instance Profile for Vault
resource "aws_iam_instance_profile" "vault" {
  name = "${var.cluster_name}-vault-profile"
  role = aws_iam_role.vault.name
}
