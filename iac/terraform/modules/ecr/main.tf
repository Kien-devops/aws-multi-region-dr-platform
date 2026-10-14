terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.tokyo]
    }
  }
}

resource "aws_ecr_repository" "this" {
  for_each             = var.repository_names
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}

resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "BASIC"
  rule {
    scan_frequency = "SCAN_ON_PUSH"
    repository_filter {
      filter      = "app2-*"
      filter_type = "WILDCARD"
    }
  }
}

resource "aws_ecr_replication_configuration" "this" {
  replication_configuration {
    rule {
      destination {
        region      = var.destination_region
        registry_id = var.account_id
      }
      repository_filter {
        filter      = "app2-"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

resource "aws_ecr_repository_creation_template" "replica" {
  provider             = aws.tokyo
  prefix               = "app2"
  description          = "Creation template for replicated app2 repositories"
  image_tag_mutability = "IMMUTABLE"
  applied_for          = ["REPLICATION"]
  encryption_configuration { encryption_type = "AES256" }
}
