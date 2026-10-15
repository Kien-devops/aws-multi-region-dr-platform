terraform {
  required_providers {
    aws        = { source = "hashicorp/aws" }
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
  }
}

locals {
  oidc_host = replace(var.oidc_issuer, "https://", "")
}

data "aws_iam_openid_connect_provider" "this" {
  url = var.oidc_issuer
}

module "role" {
  source      = "../iam_role"
  name        = var.role_name
  description = var.role_description
  assume_role_policy = var.authentication_mode == "pod_identity" ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.this.arn }
      Action    = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]
      Condition = { StringEquals = {
        "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
      } }
    }]
  })
  policy_arns = [var.policy_arn]
  tags        = var.tags
}

resource "kubernetes_service_account" "this" {
  count = var.manage_service_account || var.manage_helm ? 1 : 0
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = var.authentication_mode == "irsa" ? {
      "eks.amazonaws.com/role-arn" = module.role.arn
    } : {}
  }
}

resource "aws_eks_pod_identity_association" "this" {
  count           = var.authentication_mode == "pod_identity" ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = module.role.arn
}

resource "helm_release" "this" {
  count            = var.manage_helm ? 1 : 0
  name             = "aws-load-balancer-controller"
  namespace        = "kube-system"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = var.chart_version
  create_namespace = false
  values = [yamlencode({
    clusterName = var.cluster_name
    region      = var.region
    vpcId       = var.vpc_id
    serviceAccount = {
      create = false
      name   = "aws-load-balancer-controller"
    }
  })]
  depends_on = [kubernetes_service_account.this]
}
