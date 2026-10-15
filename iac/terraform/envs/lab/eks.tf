module "sg_eks" {
  count               = var.create_eks ? 1 : 0
  source              = "../../modules/eks"
  cluster_name        = local.sg_cluster_name
  vpc_id              = data.aws_vpc.sg.id
  private_subnet_ids  = data.aws_subnets.sg_private.ids
  admin_principal_arn = var.admin_principal_arn
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.sg_node_desired_size
}

module "tokyo_eks" {
  count               = var.create_tokyo_eks ? 1 : 0
  source              = "../../modules/eks"
  providers           = { aws = aws.tokyo }
  cluster_name        = local.tokyo_cluster_name
  vpc_id              = data.aws_vpc.tokyo.id
  private_subnet_ids  = data.aws_subnets.tokyo_private.ids
  admin_principal_arn = var.admin_principal_arn
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
}
