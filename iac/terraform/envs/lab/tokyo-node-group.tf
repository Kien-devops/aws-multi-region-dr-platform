data "aws_eks_node_group" "tokyo_existing" {
  provider        = aws.tokyo
  cluster_name    = local.tokyo_cluster_name
  node_group_name = "dr-tokyo-ng"
}

# Tokyo EKS is pre-existing and was not part of the original Terraform state.
# Import this resource before planning so only its scaling is managed here.
resource "aws_eks_node_group" "tokyo_existing" {
  provider        = aws.tokyo
  cluster_name    = data.aws_eks_node_group.tokyo_existing.cluster_name
  node_group_name = data.aws_eks_node_group.tokyo_existing.node_group_name
  node_role_arn   = data.aws_eks_node_group.tokyo_existing.node_role_arn
  subnet_ids      = data.aws_eks_node_group.tokyo_existing.subnet_ids
  capacity_type   = data.aws_eks_node_group.tokyo_existing.capacity_type
  instance_types  = data.aws_eks_node_group.tokyo_existing.instance_types
  ami_type        = data.aws_eks_node_group.tokyo_existing.ami_type
  disk_size       = data.aws_eks_node_group.tokyo_existing.disk_size

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    ignore_changes = [
      ami_type,
      capacity_type,
      disk_size,
      instance_types,
      node_role_arn,
      subnet_ids,
      update_config,
      version,
      release_version,
      tags
    ]
  }
}

resource "aws_iam_role_policy_attachment" "tokyo_node_ssm" {
  role       = "dr-tokyo-eks-node-role"
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
