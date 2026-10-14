output "sg_vpc_id" { value = data.aws_vpc.sg.id }
output "tokyo_vpc_id" { value = data.aws_vpc.tokyo.id }
output "sg_eks_cluster" { value = try(module.sg_eks[0].cluster_arn, null) }
