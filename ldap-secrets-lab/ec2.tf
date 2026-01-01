# Vault EC2 Instance
resource "aws_instance" "vault" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.vault.id]
  iam_instance_profile   = aws_iam_instance_profile.vault.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/vault-user-data.sh", {
    vault_version = var.vault_version
    vault_license = var.vault_license
    kms_key_id    = aws_kms_key.vault_unseal.key_id
    aws_region    = var.aws_region
    ldap_host     = aws_instance.ldap.private_ip
    ldap_base_dn  = local.ldap_base_dn
  }))

  tags = {
    Name = "${var.cluster_name}-vault"
  }

  depends_on = [
    aws_iam_role_policy.vault_kms,
    aws_instance.ldap
  ]
}

# OpenLDAP EC2 Instance
resource "aws_instance" "ldap" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public[1].id
  vpc_security_group_ids = [aws_security_group.ldap.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/ldap-user-data.sh", {
    ldap_domain       = var.ldap_domain
    ldap_organisation = var.ldap_organisation
    ldap_admin_pass   = var.ldap_admin_password
    enable_tls        = var.enable_ldap_tls
    ldap_base_dn      = local.ldap_base_dn
  }))

  tags = {
    Name = "${var.cluster_name}-ldap"
  }
}

# Deploy scripts to Vault instance after it's ready
resource "null_resource" "deploy_scripts" {
  triggers = {
    vault_instance_id = aws_instance.vault.id
    # Re-deploy if any script changes
    scripts_hash = sha256(join("", [
      for f in fileset("${path.module}/scripts", "*.sh") :
      filesha256("${path.module}/scripts/${f}")
    ]))
  }

  connection {
    type        = "ssh"
    host        = aws_instance.vault.public_ip
    user        = "ec2-user"
    private_key = tls_private_key.main.private_key_pem
    timeout     = "5m"
  }

  # Wait for cloud-init to complete
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "mkdir -p ~/scripts"
    ]
  }

  # Copy all scripts from local scripts/ folder
  provisioner "file" {
    source      = "${path.module}/scripts/"
    destination = "/home/ec2-user/scripts"
  }

  # Make scripts executable
  provisioner "remote-exec" {
    inline = [
      "chmod +x ~/scripts/*.sh",
      "echo 'Scripts deployed to ~/scripts/'"
    ]
  }

  depends_on = [aws_instance.vault]
}
