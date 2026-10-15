terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

resource "aws_secretsmanager_secret" "this" {
  count       = var.manage_secret ? 1 : 0
  name        = var.name
  description = var.description
  replica {
    region = var.replica_region
  }
  tags = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}
