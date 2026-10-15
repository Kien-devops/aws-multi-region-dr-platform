output "role_arn" { value = module.role.arn }
output "pod_identity_association_id" {
  value = try(aws_eks_pod_identity_association.this[0].association_id, null)
}
