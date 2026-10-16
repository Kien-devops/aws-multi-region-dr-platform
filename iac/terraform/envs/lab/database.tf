module "aurora_global" {
  count                         = var.manage_aurora ? 1 : 0
  source                        = "../../modules/aurora_global"
  providers                     = { aws = aws, aws.secondary = aws.tokyo }
  global_cluster_identifier     = var.aurora_global_cluster_identifier
  primary_cluster_identifier    = var.aurora_primary_cluster_identifier
  secondary_cluster_identifier  = var.aurora_secondary_cluster_identifier
  primary_region                = var.primary_region
  primary_subnet_group_name     = var.aurora_primary_subnet_group_name
  secondary_subnet_group_name   = var.aurora_secondary_subnet_group_name
  primary_security_group_ids    = [data.aws_security_group.aurora_primary.id]
  secondary_security_group_ids  = [data.aws_security_group.aurora_secondary.id]
  primary_instance_identifier   = var.aurora_primary_instance_identifier
  secondary_instance_identifier = var.aurora_secondary_instance_identifier
  primary_instance_class        = var.aurora_primary_instance_class
  secondary_instance_class      = var.aurora_secondary_instance_class
  primary_availability_zone     = var.aurora_primary_availability_zone
  secondary_availability_zone   = var.aurora_secondary_availability_zone
  primary_kms_key_id            = var.aurora_primary_kms_key_id
  secondary_kms_key_id          = var.aurora_secondary_kms_key_id
  primary_backup_window         = var.aurora_primary_backup_window
  secondary_backup_window       = var.aurora_secondary_backup_window
  primary_maintenance_window    = var.aurora_primary_maintenance_window
  secondary_maintenance_window  = var.aurora_secondary_maintenance_window
  primary_monitoring_role_arn   = var.aurora_monitoring_role_arn
  secondary_monitoring_role_arn = var.aurora_monitoring_role_arn
  manage_clusters               = var.manage_aurora_clusters
  tags                          = {}
}
