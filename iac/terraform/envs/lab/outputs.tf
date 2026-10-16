output "sg_vpc_id" { value = data.aws_vpc.sg.id }
output "tokyo_vpc_id" { value = data.aws_vpc.tokyo.id }
output "sg_eks_cluster" { value = try(module.sg_eks[0].cluster_arn, null) }
output "tokyo_eks_cluster" { value = try(module.tokyo_eks[0].cluster_arn, null) }
output "tokyo_lbc_role" { value = try(module.tokyo_lbc[0].role_arn, null) }
output "database_secret_arn" { value = try(module.database_secret[0].arn, null) }
output "global_accelerator_arn" { value = try(module.global_accelerator[0].accelerator_arn, null) }
output "alerts_topic_arn" { value = try(module.observability[0].topic_arn, null) }
