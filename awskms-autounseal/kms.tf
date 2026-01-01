# Get current AWS account ID
data "aws_caller_identity" "current" {}

# KMS Key for Vault Auto-Unseal
resource "aws_kms_key" "vault_unseal" {
  description             = "KMS key for Vault auto-unseal"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Vault EC2 Instances to use the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.vault.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-unseal-key"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.cluster_name}-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}
