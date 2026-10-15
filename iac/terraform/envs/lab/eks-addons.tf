module "sg_eks_addons" {
  count        = var.manage_eks_addons ? 1 : 0
  source       = "../../modules/eks_addons"
  cluster_name = try(module.sg_eks[0].cluster_name, local.sg_cluster_name)
}

module "tokyo_eks_addons" {
  count        = var.manage_tokyo_eks_addons ? 1 : 0
  source       = "../../modules/eks_addons"
  providers    = { aws = aws.tokyo }
  cluster_name = try(module.tokyo_eks[0].cluster_name, local.tokyo_cluster_name)
}
