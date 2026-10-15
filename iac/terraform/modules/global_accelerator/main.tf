terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.global]
    }
  }
}

resource "aws_globalaccelerator_accelerator" "this" {
  provider        = aws.global
  count           = var.manage ? 1 : 0
  name            = var.name
  enabled         = true
  ip_address_type = "IPV4"
  tags            = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}

resource "aws_globalaccelerator_listener" "https" {
  provider        = aws.global
  count           = var.manage ? 1 : 0
  accelerator_arn = aws_globalaccelerator_accelerator.this[0].id
  protocol        = "TCP"
  client_affinity = "NONE"
  port_range {
    from_port = 80
    to_port   = 80
  }
}

resource "aws_globalaccelerator_endpoint_group" "primary" {
  provider                = aws.global
  count                   = var.manage ? 1 : 0
  listener_arn            = aws_globalaccelerator_listener.https[0].id
  endpoint_group_region   = "ap-southeast-1"
  traffic_dial_percentage = var.primary_traffic_dial
  endpoint_configuration {
    endpoint_id = var.primary_endpoint_id
    weight      = 100
  }
}

resource "aws_globalaccelerator_endpoint_group" "secondary" {
  provider                = aws.global
  count                   = var.manage ? 1 : 0
  listener_arn            = aws_globalaccelerator_listener.https[0].id
  endpoint_group_region   = "ap-northeast-1"
  traffic_dial_percentage = var.secondary_traffic_dial
  endpoint_configuration {
    endpoint_id = var.secondary_endpoint_id
    weight      = 100
  }
}
