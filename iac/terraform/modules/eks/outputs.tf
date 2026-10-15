output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_id" { value = aws_eks_cluster.this.id }
output "cluster_arn" { value = aws_eks_cluster.this.arn }
output "cluster_endpoint" { value = aws_eks_cluster.this.endpoint }
output "cluster_oidc_issuer" { value = aws_eks_cluster.this.identity[0].oidc[0].issuer }
output "node_group_id" { value = aws_eks_node_group.this.id }
output "cluster_role_arn" { value = module.cluster_role.arn }
output "node_role_arn" { value = module.node_role.arn }
