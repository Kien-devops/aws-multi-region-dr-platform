module "sg_lbc" {
  count                  = var.create_lbc_role ? 1 : 0
  source                 = "../../modules/lbc"
  cluster_name           = try(module.sg_eks[0].cluster_name, local.sg_cluster_name)
  region                 = var.primary_region
  vpc_id                 = data.aws_vpc.sg.id
  oidc_issuer            = try(module.sg_eks[0].cluster_oidc_issuer, var.sg_oidc_issuer)
  role_name              = local.sg_lbc_role_name
  role_description       = null
  policy_arn             = data.aws_iam_policy.lbc.arn
  manage_helm            = var.manage_lbc_helm
  manage_service_account = var.manage_lbc_service_account || var.manage_lbc_helm
  authentication_mode    = var.lbc_authentication_mode
  tags                   = { Project = local.project }
}

module "tokyo_lbc" {
  count                  = var.create_tokyo_lbc_role && var.tokyo_oidc_issuer != "" ? 1 : 0
  source                 = "../../modules/lbc"
  providers              = { aws = aws.tokyo }
  cluster_name           = try(module.tokyo_eks[0].cluster_name, local.tokyo_cluster_name)
  region                 = var.secondary_region
  vpc_id                 = data.aws_vpc.tokyo.id
  oidc_issuer            = try(module.tokyo_eks[0].cluster_oidc_issuer, var.tokyo_oidc_issuer)
  role_name              = local.tokyo_lbc_role_name
  role_description       = "IRSA role for AWS Load Balancer Controller on dr-tokyo-eks"
  policy_arn             = data.aws_iam_policy.lbc_tokyo.arn
  manage_service_account = var.manage_lbc_service_account
  authentication_mode    = var.lbc_authentication_mode
  tags                   = {}
}
