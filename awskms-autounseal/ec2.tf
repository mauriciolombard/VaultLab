# Vault EC2 Instances
resource "aws_instance" "vault" {
  count = 3

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.vault.key_name
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.vault.id]
  iam_instance_profile   = aws_iam_instance_profile.vault.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/vault-user-data.sh", {
    vault_version   = var.vault_version
    vault_license   = var.vault_license
    node_id         = "vault${count.index + 1}"
    kms_key_id      = aws_kms_key.vault_unseal.key_id
    aws_region      = var.aws_region
    cluster_tag_key = "VaultCluster"
    cluster_name    = var.cluster_name
  }))

  tags = {
    Name         = "${var.cluster_name}-vault-${count.index + 1}"
    VaultCluster = var.cluster_name
  }

  # Wait for IAM instance profile to be ready
  depends_on = [
    aws_iam_role_policy.vault_kms,
    aws_iam_role_policy.vault_ec2
  ]
}
