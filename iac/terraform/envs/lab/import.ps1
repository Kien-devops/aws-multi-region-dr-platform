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
terraform import 'module.sg_eks[0].module.cluster_role.aws_iam_role.this' dr-sg-eks-cluster-role
terraform import 'module.sg_eks[0].module.node_role.aws_iam_role.this' dr-sg-eks-node-role
terraform import 'module.sg_eks[0].module.cluster_role.aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]' dr-sg-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
terraform import 'module.sg_eks[0].module.node_role.aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"]' dr-sg-eks-node-role/arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
terraform import 'module.sg_eks[0].module.node_role.aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"]' dr-sg-eks-node-role/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly
terraform import 'module.sg_eks[0].module.node_role.aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"]' dr-sg-eks-node-role/arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
terraform import 'module.sg_eks[0].aws_eks_cluster.this' dr-sg-eks
terraform import 'module.sg_eks[0].aws_eks_node_group.this' dr-sg-eks:dr-sg-ng
terraform import 'module.sg_eks[0].aws_eks_access_entry.admin' 'dr-sg-eks:arn:aws:iam::620306387033:user/kien-lvn'
terraform import 'module.sg_eks[0].aws_eks_access_policy_association.admin' 'dr-sg-eks#arn:aws:iam::620306387033:user/kien-lvn#arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy'
terraform import 'module.sg_eks[0].aws_eks_access_entry.node' 'dr-sg-eks:arn:aws:iam::620306387033:role/dr-sg-eks-node-role'

# Tokyo EKS (enable create_tokyo_eks first; verify the live version and admin ARN).
# terraform import 'module.tokyo_eks[0].aws_iam_role.cluster' dr-tokyo-eks-cluster-role
# terraform import 'module.tokyo_eks[0].aws_iam_role.node' dr-tokyo-eks-node-role
# terraform import 'module.tokyo_eks[0].aws_eks_cluster.this' dr-tokyo-eks
# terraform import 'module.tokyo_eks[0].aws_eks_node_group.this' dr-tokyo-eks:dr-tokyo-ng

# EKS managed add-ons. Import only add-ons confirmed in the console.
# terraform import 'module.sg_eks_addons[0].aws_eks_addon.this["eks-pod-identity-agent"]' dr-sg-eks:eks-pod-identity-agent
# terraform import 'module.sg_eks_addons[0].aws_eks_addon.this["amazon-cloudwatch-observability"]' dr-sg-eks:amazon-cloudwatch-observability
# terraform import 'module.tokyo_eks_addons[0].aws_eks_addon.this["eks-pod-identity-agent"]' dr-tokyo-eks:eks-pod-identity-agent
# terraform import 'module.tokyo_eks_addons[0].aws_eks_addon.this["amazon-cloudwatch-observability"]' dr-tokyo-eks:amazon-cloudwatch-observability

# Secrets Manager primary secret. Replica status is returned by AWS after import.
# terraform import 'module.database_secret[0].aws_secretsmanager_secret.this[0]' /app2/database

# Global Accelerator requires the accelerator ARN and endpoint IDs from the live account.
# terraform import 'module.global_accelerator[0].aws_globalaccelerator_accelerator.this[0]' <accelerator-arn>
# terraform import 'module.global_accelerator[0].aws_globalaccelerator_listener.https[0]' <listener-arn>
# terraform import 'module.global_accelerator[0].aws_globalaccelerator_endpoint_group.primary[0]' <primary-endpoint-group-arn>
# terraform import 'module.global_accelerator[0].aws_globalaccelerator_endpoint_group.secondary[0]' <secondary-endpoint-group-arn>

# Observability resources. Capture dashboard JSON and confirm SNS subscription before import.
# terraform import 'module.observability[0].aws_sns_topic.alerts[0]' dr-platform-alerts
# terraform import 'module.observability[0].aws_cloudwatch_dashboard.overview[0]' dr-platform-overview
# terraform import 'module.observability[0].aws_cloudwatch_metric_alarm.this["<alarm-name>"]' <alarm-name>

# AWS Load Balancer Controller Pod Identity role (policy itself already exists and is referenced as data).
terraform import 'module.sg_lbc[0].module.role.aws_iam_role.this' dr-sg-aws-lb-controller-role
terraform import 'module.sg_lbc[0].module.role.aws_iam_role_policy_attachment.this["arn:aws:iam::620306387033:policy/AWSLoadBalancerControllerIAMPolicy"]' dr-sg-aws-lb-controller-role/arn:aws:iam::620306387033:policy/AWSLoadBalancerControllerIAMPolicy
terraform import 'module.sg_lbc[0].kubernetes_service_account.this[0]' kube-system/aws-load-balancer-controller
terraform import 'module.sg_lbc[0].helm_release.this[0]' kube-system/aws-load-balancer-controller

# Full EKS Pod Identity inventory. These IDs are live associations; import before plan/apply.
terraform import 'module.sg_lbc[0].aws_eks_pod_identity_association.this[0]' 'dr-sg-eks,a-k80tt86nap6cwqjdv'
terraform import 'module.sg_eso_pod_identity[0].module.role.aws_iam_role.this' dr-sg-eso-role
terraform import 'module.sg_eso_pod_identity[0].module.role.aws_iam_role_policy_attachment.this["arn:aws:iam::620306387033:policy/App2DatabaseSecretReadPolicy"]' 'dr-sg-eso-role/arn:aws:iam::620306387033:policy/App2DatabaseSecretReadPolicy'
terraform import 'module.sg_eso_pod_identity[0].aws_eks_pod_identity_association.this' 'dr-sg-eks,a-ewbj73dmn3qrj0eun'
terraform import 'module.sg_cloudwatch_pod_identity[0].module.role.aws_iam_role.this' dr-sg-cloudwatch-agent-role
terraform import 'module.sg_cloudwatch_pod_identity[0].module.role.aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]' 'dr-sg-cloudwatch-agent-role/arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy'
terraform import 'module.sg_cloudwatch_pod_identity[0].aws_eks_pod_identity_association.this' 'dr-sg-eks,a-sgiivoy9fzbekpp9w'

terraform import 'module.tokyo_lbc[0].module.role.aws_iam_role.this' dr-tokyo-aws-lb-controller-role
terraform import 'module.tokyo_lbc[0].module.role.aws_iam_role_policy_attachment.this["arn:aws:iam::620306387033:policy/AWSLoadBalancerControllerIAMPolicy"]' 'dr-tokyo-aws-lb-controller-role/arn:aws:iam::620306387033:policy/AWSLoadBalancerControllerIAMPolicy'
terraform import 'module.tokyo_lbc[0].kubernetes_service_account.this[0]' kube-system/aws-load-balancer-controller
terraform import 'module.tokyo_lbc[0].aws_eks_pod_identity_association.this[0]' 'dr-tokyo-eks,a-ft8veinbzfrfkjej1'
terraform import 'module.tokyo_eso_pod_identity[0].module.role.aws_iam_role.this' dr-tokyo-eso-role
terraform import 'module.tokyo_eso_pod_identity[0].module.role.aws_iam_role_policy_attachment.this["arn:aws:iam::620306387033:policy/App2DatabaseSecretReadPolicy"]' 'dr-tokyo-eso-role/arn:aws:iam::620306387033:policy/App2DatabaseSecretReadPolicy'
terraform import 'module.tokyo_eso_pod_identity[0].aws_eks_pod_identity_association.this' 'dr-tokyo-eks,a-qcecptrsduvknuiwu'
terraform import 'module.tokyo_cloudwatch_pod_identity[0].module.role.aws_iam_role.this' dr-tokyo-cloudwatch-agent-role
terraform import 'module.tokyo_cloudwatch_pod_identity[0].module.role.aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]' 'dr-tokyo-cloudwatch-agent-role/arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy'
terraform import 'module.tokyo_cloudwatch_pod_identity[0].aws_eks_pod_identity_association.this' 'dr-tokyo-eks,a-pkh2pgpxv74ev7lpl'

terraform import 'module.sg_eks_addons[0].aws_eks_addon.this["eks-pod-identity-agent"]' 'dr-sg-eks:eks-pod-identity-agent'
terraform import 'module.sg_eks_addons[0].aws_eks_addon.this["amazon-cloudwatch-observability"]' 'dr-sg-eks:amazon-cloudwatch-observability'
terraform import 'module.tokyo_eks_addons[0].aws_eks_addon.this["eks-pod-identity-agent"]' 'dr-tokyo-eks:eks-pod-identity-agent'
terraform import 'module.tokyo_eks_addons[0].aws_eks_addon.this["amazon-cloudwatch-observability"]' 'dr-tokyo-eks:amazon-cloudwatch-observability'
