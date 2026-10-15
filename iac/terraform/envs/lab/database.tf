module "aurora_global" {
  count                        = var.manage_aurora ? 1 : 0
  source                       = "../../modules/aurora_global"
  providers                    = { aws = aws, aws.secondary = aws.tokyo }
  global_cluster_identifier    = var.aurora_global_cluster_identifier
  primary_cluster_identifier   = var.aurora_primary_cluster_identifier
  secondary_cluster_identifier = var.aurora_secondary_cluster_identifier
  primary_region               = var.primary_region
  primary_subnet_group_name    = var.aurora_primary_subnet_group_name
  secondary_subnet_group_name  = var.aurora_secondary_subnet_group_name
  manage_clusters              = var.manage_aurora_clusters
  tags                         = local.common_tags
}
