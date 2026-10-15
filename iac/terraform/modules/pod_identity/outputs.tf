output "role_arn" { value = module.role.arn }
output "association_id" { value = aws_eks_pod_identity_association.this.association_id }
