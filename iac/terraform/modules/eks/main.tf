terraform {
  required_providers { aws = { source = "hashicorp/aws" } }
}

data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

module "cluster_role" {
  source             = "../iam_role"
  name               = "${var.cluster_name}-cluster-role"
  description        = "IAM role for EKS control plane ${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
  policy_arns        = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
  tags               = var.tags
}

module "node_role" {
  source             = "../iam_role"
  name               = "${var.cluster_name}-node-role"
  description        = "IAM role for EKS managed node group ${var.cluster_name == "dr-sg-eks" ? "dr-sg-ng" : "dr-tokyo-ng"}"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  tags = var.tags
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = module.cluster_role.arn
  version  = var.kubernetes_version
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  deletion_protection       = true
  tags                      = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
  lifecycle {
    ignore_changes = [zonal_shift_config]
  }
  depends_on = [module.cluster_role]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.cluster_name == "dr-sg-eks" ? "dr-sg-ng" : "dr-tokyo-ng"
  node_role_arn   = module.node_role.arn
  subnet_ids      = var.private_subnet_ids
  capacity_type   = var.node_capacity_type
  instance_types  = var.node_instance_types
  ami_type        = "AL2023_x86_64_STANDARD"
  disk_size       = 30
  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }
  update_config {
    max_unavailable = 1
    update_strategy = "DEFAULT"
  }
  depends_on = [aws_eks_cluster.this, module.node_role]
  tags       = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}

resource "aws_eks_access_entry" "node" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = module.node_role.arn
  type          = "EC2_LINUX"
}
