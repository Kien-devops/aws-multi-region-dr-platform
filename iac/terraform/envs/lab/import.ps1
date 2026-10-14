# Import-only migration helper. Set all create_* flags to true in terraform.tfvars first.
# Review every command and stop on the first unexpected error.

$ErrorActionPreference = "Stop"

$TerraformExecutable = (Get-Command terraform -CommandType Application).Source
$ManagedResources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
& $TerraformExecutable state list | ForEach-Object { [void]$ManagedResources.Add($_) }
if ($LASTEXITCODE -ne 0) { throw "Unable to read the current Terraform state." }

function terraform {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$TerraformArgs)

  if ($TerraformArgs.Count -ge 2 -and $TerraformArgs[0] -eq "import" -and $ManagedResources.Contains($TerraformArgs[1])) {
    Write-Host "Already imported: $($TerraformArgs[1])"
    return
  }

  # cmd preserves the quoted for_each key that Windows PowerShell strips.
  $InvokeArgs = $TerraformArgs | ForEach-Object { $_ -replace '"', '\"' }
  $CommandLine = '"{0}" {1}' -f $TerraformExecutable, ($InvokeArgs -join ' ')
  & cmd.exe /d /s /c $CommandLine
  if ($LASTEXITCODE -ne 0) { throw "Terraform command failed: terraform $($TerraformArgs -join ' ')" }

  if ($TerraformArgs.Count -ge 2 -and $TerraformArgs[0] -eq "import") {
    [void]$ManagedResources.Add($TerraformArgs[1])
  }
}

# VPC foundations
terraform import 'module.sg_network[0].aws_vpc.this' vpc-035e691629f36584e
terraform import 'module.sg_network[0].aws_internet_gateway.this' igw-07affec6fb6cdbaf4
terraform import 'module.sg_network[0].aws_subnet.public["ap-southeast-1a"]' subnet-0f87600fc7d4e7542
terraform import 'module.sg_network[0].aws_subnet.public["ap-southeast-1b"]' subnet-07de14df4462e4426
terraform import 'module.sg_network[0].aws_subnet.private["ap-southeast-1a"]' subnet-03809e63730d55a47
terraform import 'module.sg_network[0].aws_subnet.private["ap-southeast-1b"]' subnet-03d7225a8cabcab5f
terraform import 'module.sg_network[0].aws_route_table.public' rtb-0c4d2a5f948868588
terraform import 'module.sg_network[0].aws_route_table.private' rtb-08da5562a522775e9
terraform import 'module.sg_network[0].aws_route_table_association.public["ap-southeast-1a"]' subnet-0f87600fc7d4e7542/rtb-0c4d2a5f948868588
terraform import 'module.sg_network[0].aws_route_table_association.public["ap-southeast-1b"]' subnet-07de14df4462e4426/rtb-0c4d2a5f948868588
terraform import 'module.sg_network[0].aws_route_table_association.private["ap-southeast-1a"]' subnet-03809e63730d55a47/rtb-08da5562a522775e9
terraform import 'module.sg_network[0].aws_route_table_association.private["ap-southeast-1b"]' subnet-03d7225a8cabcab5f/rtb-08da5562a522775e9
terraform import 'module.sg_network[0].aws_nat_gateway.this' nat-03898959bf2c6e284
terraform import 'module.sg_network[0].aws_eip.nat' eipalloc-0854805aad7065c68
terraform import 'module.sg_network[0].aws_security_group.fsx' sg-0776992793aac17e6
terraform import 'module.sg_network[0].aws_vpc_security_group_egress_rule.fsx_all' sgr-02d464659351903fd
terraform import 'module.sg_network[0].aws_vpc_security_group_ingress_rule.fsx_tcp["postgres-10.20.11.0-24"]' sgr-019803a830f447ba0
terraform import 'module.sg_network[0].aws_vpc_security_group_ingress_rule.fsx_tcp["postgres-10.20.12.0-24"]' sgr-00586dd738907502b
terraform import 'module.sg_network[0].aws_vpc_security_group_ingress_rule.fsx_tcp["ndmp"]' sgr-0d0ea9d4786a9139c
terraform import 'module.sg_network[0].aws_vpc_security_group_ingress_rule.fsx_tcp["https"]' sgr-02019b47c3799fd2d
terraform import 'module.sg_network[0].aws_vpc_security_group_ingress_rule.fsx_snapmirror' sgr-0f6e7ee3fea757a38
terraform import 'module.sg_network[0].aws_vpc_security_group_ingress_rule.fsx_icmp' sgr-03bab5c0f7d2141a7

terraform import 'module.tokyo_network[0].aws_vpc.this' vpc-014bd2b27411c1b8a
terraform import 'module.tokyo_network[0].aws_internet_gateway.this' igw-0338023d4e943ecd1
terraform import 'module.tokyo_network[0].aws_subnet.public["ap-northeast-1a"]' subnet-04cefdc90f2bd174e
terraform import 'module.tokyo_network[0].aws_subnet.public["ap-northeast-1c"]' subnet-0517660146b9d78b4
terraform import 'module.tokyo_network[0].aws_subnet.private["ap-northeast-1a"]' subnet-0182665226e778b3a
terraform import 'module.tokyo_network[0].aws_subnet.private["ap-northeast-1c"]' subnet-0c2b4194d57b4ac15
terraform import 'module.tokyo_network[0].aws_route_table.public' rtb-0a65c3dcaefe5acc6
terraform import 'module.tokyo_network[0].aws_route_table.private' rtb-05d2b70f8be52735d
terraform import 'module.tokyo_network[0].aws_route_table_association.public["ap-northeast-1a"]' subnet-04cefdc90f2bd174e/rtb-0a65c3dcaefe5acc6
terraform import 'module.tokyo_network[0].aws_route_table_association.public["ap-northeast-1c"]' subnet-0517660146b9d78b4/rtb-0a65c3dcaefe5acc6
terraform import 'module.tokyo_network[0].aws_route_table_association.private["ap-northeast-1a"]' subnet-0182665226e778b3a/rtb-05d2b70f8be52735d
terraform import 'module.tokyo_network[0].aws_route_table_association.private["ap-northeast-1c"]' subnet-0c2b4194d57b4ac15/rtb-05d2b70f8be52735d
terraform import 'module.tokyo_network[0].aws_nat_gateway.this' nat-0136040978fdc339b
terraform import 'module.tokyo_network[0].aws_eip.nat' eipalloc-0dd6a990f7f875305
terraform import 'module.tokyo_network[0].aws_security_group.fsx' sg-0333ec462c106afaf
terraform import 'module.tokyo_network[0].aws_vpc_security_group_egress_rule.fsx_all' sgr-00e96b946516104be
terraform import 'module.tokyo_network[0].aws_vpc_security_group_ingress_rule.fsx_tcp["postgres-10.10.11.0-24"]' sgr-058e4ed3740fdffca
terraform import 'module.tokyo_network[0].aws_vpc_security_group_ingress_rule.fsx_tcp["postgres-10.10.12.0-24"]' sgr-019ebf4fa3a51fcf1
terraform import 'module.tokyo_network[0].aws_vpc_security_group_ingress_rule.fsx_tcp["ndmp"]' sgr-0d10fd40dc29296eb
terraform import 'module.tokyo_network[0].aws_vpc_security_group_ingress_rule.fsx_tcp["https"]' sgr-0f6ee63a01d9cd100
terraform import 'module.tokyo_network[0].aws_vpc_security_group_ingress_rule.fsx_snapmirror' sgr-0fd019c0cee635077
terraform import 'module.tokyo_network[0].aws_vpc_security_group_ingress_rule.fsx_icmp' sgr-06a228456ae9d06f8

terraform import 'aws_vpc_peering_connection.sg_to_tokyo[0]' pcx-0cbc2b7685a2cfe78
terraform import 'aws_vpc_peering_connection_accepter.tokyo[0]' pcx-0cbc2b7685a2cfe78
terraform import 'aws_vpc_peering_connection_options.requester[0]' pcx-0cbc2b7685a2cfe78
terraform import 'aws_vpc_peering_connection_options.accepter[0]' pcx-0cbc2b7685a2cfe78
terraform import 'aws_route.sg_to_tokyo[0]' rtb-08da5562a522775e9_10.20.0.0/16
terraform import 'aws_route.tokyo_to_sg[0]' rtb-05d2b70f8be52735d_10.10.0.0/16

# ECR primary registry and repository objects
foreach ($name in @("app2-frontend", "app2-backend-1", "app2-backend-2", "app2-backend-3", "app2-file-service")) {
  terraform import ('module.ecr[0].aws_ecr_repository.this["{0}"]' -f $name) $name
}
terraform import 'module.ecr[0].aws_ecr_registry_scanning_configuration.this' 620306387033
terraform import 'module.ecr[0].aws_ecr_replication_configuration.this' 620306387033
terraform import 'module.ecr[0].aws_ecr_repository_creation_template.replica' app2

# Singapore EKS and IAM. Existing cluster is live at Kubernetes 1.37.
terraform import 'module.sg_eks[0].aws_iam_role.cluster' dr-sg-eks-cluster-role
terraform import 'module.sg_eks[0].aws_iam_role.node' dr-sg-eks-node-role
terraform import 'module.sg_eks[0].aws_iam_role_policy_attachment.cluster' dr-sg-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
terraform import 'module.sg_eks[0].aws_iam_role_policy_attachment.node["arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"]' dr-sg-eks-node-role/arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
terraform import 'module.sg_eks[0].aws_iam_role_policy_attachment.node["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"]' dr-sg-eks-node-role/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly
terraform import 'module.sg_eks[0].aws_iam_role_policy_attachment.node["arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"]' dr-sg-eks-node-role/arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
terraform import 'module.sg_eks[0].aws_eks_cluster.this' dr-sg-eks
terraform import 'module.sg_eks[0].aws_eks_node_group.this' dr-sg-eks:dr-sg-ng
terraform import 'module.sg_eks[0].aws_eks_access_entry.admin' 'dr-sg-eks:arn:aws:iam::620306387033:user/kien-lvn'
terraform import 'module.sg_eks[0].aws_eks_access_policy_association.admin' 'dr-sg-eks#arn:aws:iam::620306387033:user/kien-lvn#arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy'
terraform import 'module.sg_eks[0].aws_eks_access_entry.node' 'dr-sg-eks:arn:aws:iam::620306387033:role/dr-sg-eks-node-role'

# AWS Load Balancer Controller IRSA role (policy itself already exists and is referenced as data).
terraform import 'module.sg_lbc[0].aws_iam_role.this' dr-sg-aws-lb-controller-role
terraform import 'module.sg_lbc[0].aws_iam_role_policy_attachment.this' dr-sg-aws-lb-controller-role/arn:aws:iam::620306387033:policy/AWSLoadBalancerControllerIAMPolicy
terraform import 'module.sg_lbc[0].kubernetes_service_account.this[0]' kube-system/aws-load-balancer-controller
terraform import 'module.sg_lbc[0].helm_release.this[0]' kube-system/aws-load-balancer-controller
