# OpenLDAP Server EC2 Instance

resource "aws_instance" "openldap" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.available.ids[0]
  vpc_security_group_ids      = [aws_security_group.ldap.id]
  key_name                    = aws_key_pair.ldap.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/openldap-user-data.sh", {
    ldap_domain             = var.ldap_domain
    ldap_admin_password     = var.ldap_admin_password
    ldap_test_user_password = var.ldap_test_user_password
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.cluster_name}-openldap"
  }

  # Wait for instance to be ready before configuring Vault
  provisioner "local-exec" {
    command = "echo 'Waiting for OpenLDAP server to initialize...' && sleep 60"
  }
}
