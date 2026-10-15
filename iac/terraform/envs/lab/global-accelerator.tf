module "global_accelerator" {
  count                 = var.manage_global_accelerator ? 1 : 0
  source                = "../../modules/global_accelerator"
  providers             = { aws.global = aws.global }
  name                  = "dr-global-accelerator"
  primary_endpoint_id   = var.global_accelerator_primary_endpoint_id
  secondary_endpoint_id = var.global_accelerator_secondary_endpoint_id
  manage                = true
  tags                  = local.common_tags
}
