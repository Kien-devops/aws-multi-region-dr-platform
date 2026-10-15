terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

module "role" {
  source      = "../iam_role"
  name        = var.role_name
  description = var.description
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  policy_arns = var.policy_arns
  tags        = var.tags
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = module.role.arn
  tags            = var.tags

  lifecycle {
    # Do not rewrite console-added association metadata during codification.
    ignore_changes = [tags]
  }
}
