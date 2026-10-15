module "database_secret" {
  count          = var.manage_secret_replication ? 1 : 0
  source         = "../../modules/secrets_replica"
  name           = var.secret_name
  replica_region = var.secondary_region
  description    = "App2 database credentials replicated to Tokyo"
  manage_secret  = true
  tags           = local.common_tags
}
