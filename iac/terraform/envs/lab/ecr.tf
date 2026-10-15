module "ecr" {
  count              = var.create_ecr ? 1 : 0
  source             = "../../modules/ecr"
  providers          = { aws = aws, aws.tokyo = aws.tokyo }
  repository_names   = var.ecr_repository_names
  destination_region = var.secondary_region
  account_id         = var.account_id
}
