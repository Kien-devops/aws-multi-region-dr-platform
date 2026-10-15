terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.peer]
    }
  }
}

resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  peer_region = var.peer_region
  auto_accept = false
  tags        = { Name = "dr-sg-to-tokyo-peering" }
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  provider                  = aws.peer
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
  auto_accept               = true
  tags                      = { Name = "dr-sg-to-tokyo-peering" }
}

resource "aws_vpc_peering_connection_options" "requester" {
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
  requester { allow_remote_vpc_dns_resolution = true }
}

resource "aws_vpc_peering_connection_options" "accepter" {
  provider                  = aws.peer
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.peer.id
  accepter { allow_remote_vpc_dns_resolution = true }
}

resource "aws_route" "requester_to_peer" {
  route_table_id            = var.requester_private_route_table_id
  destination_cidr_block    = var.requester_route_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

resource "aws_route" "peer_to_requester" {
  provider                  = aws.peer
  route_table_id            = var.accepter_private_route_table_id
  destination_cidr_block    = var.accepter_route_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}
