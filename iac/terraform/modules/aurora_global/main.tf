terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.secondary]
    }
  }
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = var.global_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = true
  tags                      = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}

resource "aws_rds_cluster" "primary" {
  count                     = var.manage_clusters ? 1 : 0
  cluster_identifier        = var.primary_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this.id
  db_subnet_group_name      = var.primary_subnet_group_name
  vpc_security_group_ids    = var.primary_security_group_ids
  storage_encrypted         = true
  deletion_protection       = true
  skip_final_snapshot       = false
  tags                      = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}

resource "aws_rds_cluster" "secondary" {
  provider                  = aws.secondary
  count                     = var.manage_clusters ? 1 : 0
  cluster_identifier        = var.secondary_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this.id
  source_region             = var.primary_region
  db_subnet_group_name      = var.secondary_subnet_group_name
  vpc_security_group_ids    = var.secondary_security_group_ids
  storage_encrypted         = true
  deletion_protection       = true
  skip_final_snapshot       = false
  tags                      = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}
