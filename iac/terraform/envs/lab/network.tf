module "sg_network" {
  count                          = var.create_network ? 1 : 0
  source                         = "../../modules/vpc"
  name                           = local.sg_name
  fsx_security_group_description = "Security group for FSx ONTAP Singapore NFS and SnapMirror"
  region                         = var.primary_region
  vpc_cidr                       = var.sg_vpc_cidr
  availability_zones             = var.sg_availability_zones
  public_subnets                 = var.sg_public_subnets
  private_subnets                = var.sg_private_subnets
  peer_cidr                      = var.tokyo_vpc_cidr
  peer_private_cidrs             = values(var.tokyo_private_subnets)
}

module "tokyo_network" {
  count                          = var.create_network ? 1 : 0
  source                         = "../../modules/vpc"
  providers                      = { aws = aws.tokyo }
  name                           = local.tokyo_name
  fsx_security_group_description = "Security group for FSx ONTAP Tokyo NFS and SnapMirror destination"
  region                         = var.secondary_region
  vpc_cidr                       = var.tokyo_vpc_cidr
  availability_zones             = var.tokyo_availability_zones
  public_subnets                 = var.tokyo_public_subnets
  private_subnets                = var.tokyo_private_subnets
  peer_cidr                      = var.sg_vpc_cidr
  peer_private_cidrs             = values(var.sg_private_subnets)
}

module "cross_region_network" {
  count                            = var.create_network ? 1 : 0
  source                           = "../../modules/vpc_peering"
  providers                        = { aws = aws, aws.peer = aws.tokyo }
  requester_vpc_id                 = module.sg_network[0].vpc_id
  accepter_vpc_id                  = module.tokyo_network[0].vpc_id
  peer_region                      = var.secondary_region
  requester_private_route_table_id = module.sg_network[0].private_route_table_id
  accepter_private_route_table_id  = module.tokyo_network[0].private_route_table_id
  requester_route_cidr             = var.tokyo_vpc_cidr
  accepter_route_cidr              = var.sg_vpc_cidr
  tags                             = var.tags
}
