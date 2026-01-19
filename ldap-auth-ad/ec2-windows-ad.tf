# Windows Server EC2 Instance with Active Directory

resource "aws_instance" "windows_ad" {
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.available.ids[0]
  vpc_security_group_ids      = [aws_security_group.ad.id]
  key_name                    = aws_key_pair.ad.key_name
  associate_public_ip_address = true
  get_password_data           = true

  user_data = templatefile("${path.module}/templates/ad-user-data.ps1", {
    ad_domain_name        = var.ad_domain_name
    ad_netbios_name       = var.ad_netbios_name
    ad_safe_mode_password = var.ad_safe_mode_password
    ad_admin_password     = var.ad_admin_password
    ad_test_user_password = var.ad_test_user_password
  })

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.cluster_name}-windows-ad"
  }

  # Windows takes longer to initialize - wait for AD setup
  timeouts {
    create = "30m"
  }
}

# Wait for Windows to be ready (RDP available)
resource "null_resource" "wait_for_windows" {
  depends_on = [aws_instance.windows_ad]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Windows Server to initialize..."
      echo "This may take 10-15 minutes for AD DS installation and configuration."
      sleep 300
      echo "Windows AD server should be ready. Check RDP connectivity."
    EOT
  }
}
