module "sg_eso_pod_identity" {
  count           = var.manage_platform_pod_identity ? 1 : 0
  source          = "../../modules/pod_identity"
  cluster_name    = try(module.sg_eks[0].cluster_name, local.sg_cluster_name)
  namespace       = local.eso_namespace
  service_account = local.eso_service_account
  role_name       = local.sg_eso_role_name
  policy_arns     = ["arn:aws:iam::${var.account_id}:policy/App2DatabaseSecretReadPolicy"]
  description     = "IRSA role for External Secrets Operator on Singapore EKS"
}

module "sg_cloudwatch_pod_identity" {
  count           = var.manage_platform_pod_identity ? 1 : 0
  source          = "../../modules/pod_identity"
  cluster_name    = try(module.sg_eks[0].cluster_name, local.sg_cluster_name)
  namespace       = local.cloudwatch_namespace
  service_account = local.cloudwatch_service_account
  role_name       = local.sg_cloudwatch_role_name
  policy_arns     = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
  description     = "EKS Pod Identity role for CloudWatch Observability on Singapore EKS"
}

module "tokyo_eso_pod_identity" {
  count           = var.manage_platform_pod_identity ? 1 : 0
  source          = "../../modules/pod_identity"
  providers       = { aws = aws.tokyo }
  cluster_name    = try(module.tokyo_eks[0].cluster_name, local.tokyo_cluster_name)
  namespace       = local.eso_namespace
  service_account = local.eso_service_account
  role_name       = local.tokyo_eso_role_name
  policy_arns     = ["arn:aws:iam::${var.account_id}:policy/App2DatabaseSecretReadPolicy"]
  description     = "IRSA role for External Secrets Operator on Tokyo EKS"
}

module "tokyo_cloudwatch_pod_identity" {
  count           = var.manage_platform_pod_identity ? 1 : 0
  source          = "../../modules/pod_identity"
  providers       = { aws = aws.tokyo }
  cluster_name    = try(module.tokyo_eks[0].cluster_name, local.tokyo_cluster_name)
  namespace       = local.cloudwatch_namespace
  service_account = local.cloudwatch_service_account
  role_name       = local.tokyo_cloudwatch_role_name
  policy_arns     = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
  description     = "EKS Pod Identity role for CloudWatch Observability on Tokyo EKS"
}
