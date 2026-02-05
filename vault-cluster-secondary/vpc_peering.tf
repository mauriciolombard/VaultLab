# VPC Peering Connection Request to Primary Cluster
resource "aws_vpc_peering_connection" "to_primary" {
  vpc_id      = aws_vpc.vault.id
  peer_vpc_id = var.primary_vpc_id
  auto_accept = false # Accepter is in the primary cluster's Terraform

  tags = {
    Name = "${var.cluster_name}-to-primary-peering"
    Side = "Requester"
  }
}

# Route to primary VPC (for replication traffic)
resource "aws_route" "to_primary_vpc" {
  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.to_primary.id
}
