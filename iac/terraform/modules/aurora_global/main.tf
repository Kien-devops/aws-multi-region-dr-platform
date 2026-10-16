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
  deletion_protection       = false
  tags                      = var.tags
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
  deletion_protection       = false
  copy_tags_to_snapshot     = true
  iam_database_authentication_enabled = true
  performance_insights_enabled = true
  performance_insights_kms_key_id = var.primary_kms_key_id
  performance_insights_retention_period = 7
  kms_key_id                 = var.primary_kms_key_id
  skip_final_snapshot       = true
  tags                      = var.tags
}

resource "aws_rds_cluster" "secondary" {
  provider                  = aws.secondary
  count                     = var.manage_clusters ? 1 : 0
  cluster_identifier        = var.secondary_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this.id
  db_subnet_group_name      = var.secondary_subnet_group_name
  vpc_security_group_ids    = var.secondary_security_group_ids
  storage_encrypted         = true
  deletion_protection       = false
  copy_tags_to_snapshot     = true
  iam_database_authentication_enabled = true
  performance_insights_enabled = true
  performance_insights_kms_key_id = var.secondary_kms_key_id
  performance_insights_retention_period = 7
  kms_key_id                 = var.secondary_kms_key_id
  skip_final_snapshot       = true
  tags                      = var.tags
  lifecycle {
    # AWS reports the original replication source for an imported global secondary;
    # it is immutable membership metadata, not a desired topology change.
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count                        = var.manage_clusters ? 1 : 0
  identifier                   = var.primary_instance_identifier
  cluster_identifier           = aws_rds_cluster.primary[0].id
  instance_class               = var.primary_instance_class
  engine                      = var.engine
  engine_version              = var.engine_version
  availability_zone           = var.primary_availability_zone
  auto_minor_version_upgrade  = true
  db_parameter_group_name     = "default.aurora-postgresql17"
  monitoring_interval         = 60
  monitoring_role_arn         = var.primary_monitoring_role_arn
  performance_insights_enabled = true
  performance_insights_kms_key_id = var.primary_kms_key_id
  performance_insights_retention_period = 7
  preferred_backup_window     = var.primary_backup_window
  preferred_maintenance_window = var.primary_maintenance_window
  promotion_tier              = 0
  publicly_accessible         = false
  copy_tags_to_snapshot       = false
  tags                        = var.tags
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                    = aws.secondary
  count                       = var.manage_clusters ? 1 : 0
  identifier                  = var.secondary_instance_identifier
  cluster_identifier          = aws_rds_cluster.secondary[0].id
  instance_class              = var.secondary_instance_class
  engine                     = var.engine
  engine_version             = var.engine_version
  availability_zone          = var.secondary_availability_zone
  auto_minor_version_upgrade = true
  db_parameter_group_name    = "default.aurora-postgresql17"
  monitoring_interval        = 60
  monitoring_role_arn        = var.secondary_monitoring_role_arn
  performance_insights_enabled = true
  performance_insights_kms_key_id = var.secondary_kms_key_id
  performance_insights_retention_period = 7
  preferred_backup_window    = var.secondary_backup_window
  preferred_maintenance_window = "sun:15:41-sun:16:11"
  promotion_tier             = 1
  publicly_accessible        = false
  copy_tags_to_snapshot      = true
  tags                       = var.tags
}
