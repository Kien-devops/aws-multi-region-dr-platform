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

resource "aws_iam_role" "this" {
  name = var.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.this.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
      } }
    }]
  })
  tags = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = var.policy_arn
}

resource "kubernetes_service_account" "this" {
  count = var.manage_helm ? 1 : 0
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
    }
  }
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
