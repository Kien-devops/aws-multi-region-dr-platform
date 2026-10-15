locals {
  project     = "aws-multi-region-dr-platform"
  environment = "lab"

  common_tags = merge(var.tags, {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
  })

  sg_name    = "dr-sg"
  tokyo_name = "dr-tokyo"

  eso_namespace              = "external-secrets"
  eso_service_account        = "external-secrets"
  cloudwatch_namespace       = "amazon-cloudwatch"
  cloudwatch_service_account = "cloudwatch-agent"

  sg_cluster_name    = "dr-sg-eks"
  tokyo_cluster_name = "dr-tokyo-eks"

  sg_lbc_role_name           = "dr-sg-aws-lb-controller-role"
  tokyo_lbc_role_name        = "dr-tokyo-aws-lb-controller-role"
  sg_eso_role_name           = "dr-sg-eso-role"
  tokyo_eso_role_name        = "dr-tokyo-eso-role"
  sg_cloudwatch_role_name    = "dr-sg-cloudwatch-agent-role"
  tokyo_cloudwatch_role_name = "dr-tokyo-cloudwatch-agent-role"
}
