data "aws_vpc" "sg" {
  filter {
    name   = "tag:Name"
    values = ["dr-sg-vpc"]
  }
}

data "aws_vpc" "tokyo" {
  provider = aws.tokyo
  filter {
    name   = "tag:Name"
    values = ["dr-tokyo-vpc"]
  }
}
data "aws_iam_policy" "lbc" { arn = "arn:aws:iam::${var.account_id}:policy/AWSLoadBalancerControllerIAMPolicy" }

module "sg_network" {
  count                          = var.create_network ? 1 : 0
  source                         = "../../modules/vpc"
  name                           = "dr-sg"
  fsx_security_group_description = "Security group for FSx ONTAP Singapore NFS and SnapMirror"
  region                         = var.primary_region
  vpc_cidr                       = "10.10.0.0/16"
  availability_zones             = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnets                 = { "ap-southeast-1a" = "10.10.1.0/24", "ap-southeast-1b" = "10.10.2.0/24" }
  private_subnets                = { "ap-southeast-1a" = "10.10.11.0/24", "ap-southeast-1b" = "10.10.12.0/24" }
  peer_cidr                      = "10.20.0.0/16"
  peer_private_cidrs             = ["10.20.11.0/24", "10.20.12.0/24"]
  peer_id                        = null
}

module "tokyo_network" {
  count                          = var.create_network ? 1 : 0
  source                         = "../../modules/vpc"
  providers                      = { aws = aws.tokyo }
  name                           = "dr-tokyo"
  fsx_security_group_description = "Security group for FSx ONTAP Tokyo NFS and SnapMirror destination"
  region                         = var.secondary_region
  vpc_cidr                       = "10.20.0.0/16"
  availability_zones             = ["ap-northeast-1a", "ap-northeast-1c"]
  public_subnets                 = { "ap-northeast-1a" = "10.20.1.0/24", "ap-northeast-1c" = "10.20.2.0/24" }
  private_subnets                = { "ap-northeast-1a" = "10.20.11.0/24", "ap-northeast-1c" = "10.20.12.0/24" }
  peer_cidr                      = "10.10.0.0/16"
  peer_private_cidrs             = ["10.10.11.0/24", "10.10.12.0/24"]
  peer_id                        = null
}

resource "aws_vpc_peering_connection" "sg_to_tokyo" {
  count       = var.create_network ? 1 : 0
  vpc_id      = var.create_network ? module.sg_network[0].vpc_id : data.aws_vpc.sg.id
  peer_vpc_id = var.create_network ? module.tokyo_network[0].vpc_id : data.aws_vpc.tokyo.id
  peer_region = var.secondary_region
  auto_accept = false
  tags        = { Name = "dr-sg-to-tokyo-peering" }
}

resource "aws_vpc_peering_connection_accepter" "tokyo" {
  count                     = var.create_network ? 1 : 0
  provider                  = aws.tokyo
  vpc_peering_connection_id = aws_vpc_peering_connection.sg_to_tokyo[0].id
  auto_accept               = true
  tags                      = { Name = "dr-sg-to-tokyo-peering" }
}

resource "aws_vpc_peering_connection_options" "requester" {
  count                     = var.create_network ? 1 : 0
  vpc_peering_connection_id = aws_vpc_peering_connection.sg_to_tokyo[0].id
  requester { allow_remote_vpc_dns_resolution = true }
}

resource "aws_vpc_peering_connection_options" "accepter" {
  count                     = var.create_network ? 1 : 0
  provider                  = aws.tokyo
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.tokyo[0].id
  accepter { allow_remote_vpc_dns_resolution = true }
}

module "ecr" {
  count              = var.create_ecr ? 1 : 0
  source             = "../../modules/ecr"
  providers          = { aws = aws, aws.tokyo = aws.tokyo }
  repository_names   = toset(["app2-frontend", "app2-backend-1", "app2-backend-2", "app2-backend-3", "app2-file-service"])
  destination_region = var.secondary_region
  account_id         = var.account_id
}

module "sg_eks" {
  count               = var.create_eks ? 1 : 0
  source              = "../../modules/eks"
  cluster_name        = "dr-sg-eks"
  vpc_id              = data.aws_vpc.sg.id
  private_subnet_ids  = data.aws_subnets.sg_private.ids
  admin_principal_arn = var.admin_principal_arn
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
}

data "aws_subnets" "sg_private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.sg.id]
  }
  filter {
    name   = "tag:Name"
    values = ["dr-sg-private-*"]
  }
}

resource "aws_route" "sg_to_tokyo" {
  count                     = var.create_network ? 1 : 0
  route_table_id            = module.sg_network[0].private_route_table_id
  destination_cidr_block    = "10.20.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.sg_to_tokyo[0].id
}

resource "aws_route" "tokyo_to_sg" {
  provider                  = aws.tokyo
  count                     = var.create_network ? 1 : 0
  route_table_id            = module.tokyo_network[0].private_route_table_id
  destination_cidr_block    = "10.10.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.sg_to_tokyo[0].id
}

module "sg_lbc" {
  count        = var.create_lbc_role ? 1 : 0
  source       = "../../modules/lbc"
  cluster_name = "dr-sg-eks"
  region       = var.primary_region
  vpc_id       = data.aws_vpc.sg.id
  oidc_issuer  = "https://oidc.eks.ap-southeast-1.amazonaws.com/id/5FDE238D7D555C338C7D6A1B8D15E167"
  role_name    = "dr-sg-aws-lb-controller-role"
  policy_arn   = data.aws_iam_policy.lbc.arn
  manage_helm  = var.manage_lbc_helm
}
