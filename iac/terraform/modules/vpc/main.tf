terraform {
  required_providers { aws = { source = "hashicorp/aws" } }
}

locals {
  common_tags = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, {
    Name                     = "${var.name}-public-${substr(each.key, -1, 1)}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  for_each          = var.private_subnets
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key
  tags = merge(local.common_tags, {
    Name                              = "${var.name}-private-${substr(each.key, -1, 1)}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.availability_zones[0]].id
  depends_on    = [aws_internet_gateway.this]
  tags          = merge(local.common_tags, { Name = "${var.name}-nat" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(local.common_tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  dynamic "route" {
    for_each = var.peer_id == null ? [] : [var.peer_id]
    content {
      cidr_block                = var.peer_cidr
      vpc_peering_connection_id = route.value
    }
  }
  tags = merge(local.common_tags, { Name = "${var.name}-private-rt" })

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "public" {
  for_each       = var.public_subnets
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each       = var.private_subnets
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "fsx" {
  name        = "${var.name}-fsx-sg"
  description = var.fsx_security_group_description
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.common_tags, { Name = "${var.name}-fsx-sg" })
}

resource "aws_vpc_security_group_egress_rule" "fsx_all" {
  security_group_id = aws_security_group.fsx.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "fsx_tcp" {
  for_each = merge(
    { for cidr in var.peer_private_cidrs : "postgres-${replace(cidr, "/", "-")}" => { cidr = cidr, port = 5432 } },
    { ndmp = { cidr = var.peer_cidr, port = 10000 }, https = { cidr = var.peer_cidr, port = 443 } }
  )
  security_group_id = aws_security_group.fsx.id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "fsx_snapmirror" {
  security_group_id = aws_security_group.fsx.id
  cidr_ipv4         = var.peer_cidr
  from_port         = 11104
  to_port           = 11105
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "fsx_icmp" {
  security_group_id = aws_security_group.fsx.id
  cidr_ipv4         = var.peer_cidr
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}
