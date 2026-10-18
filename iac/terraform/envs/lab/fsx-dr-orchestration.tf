module "fsx_dr_orchestration" {
  count  = var.enable_fsx_dr_orchestration ? 1 : 0
  source = "../../modules/fsx_dr_orchestration"

  providers = { aws = aws.tokyo }

  region                      = var.secondary_region
  vpc_id                      = data.aws_vpc.tokyo.id
  vpc_subnet_ids              = data.aws_subnets.tokyo_private.ids
  alarm_names                 = var.fsx_dr_alarm_names
  ontap_management_secret_arn = var.fsx_dr_ontap_management_secret_arn
  gitops_secret_arn           = var.fsx_dr_gitops_secret_arn
  file_service_url            = var.fsx_dr_file_service_url
  enable_event_trigger        = var.enable_fsx_dr_event_trigger
  enable_promotion            = var.enable_fsx_dr_promotion
  enable_traffic_switch       = var.enable_fsx_dr_traffic_switch
  tags                        = local.common_tags
}
