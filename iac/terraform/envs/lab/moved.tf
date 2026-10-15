moved {
  from = aws_vpc_peering_connection.sg_to_tokyo[0]
  to   = module.cross_region_network[0].aws_vpc_peering_connection.this
}
moved {
  from = aws_vpc_peering_connection_accepter.tokyo[0]
  to   = module.cross_region_network[0].aws_vpc_peering_connection_accepter.peer
}
moved {
  from = aws_vpc_peering_connection_options.requester[0]
  to   = module.cross_region_network[0].aws_vpc_peering_connection_options.requester
}
moved {
  from = aws_vpc_peering_connection_options.accepter[0]
  to   = module.cross_region_network[0].aws_vpc_peering_connection_options.accepter
}
moved {
  from = aws_route.sg_to_tokyo[0]
  to   = module.cross_region_network[0].aws_route.requester_to_peer
}
moved {
  from = aws_route.tokyo_to_sg[0]
  to   = module.cross_region_network[0].aws_route.peer_to_requester
}
moved {
  from = module.sg_eks[0].aws_iam_role.cluster
  to   = module.sg_eks[0].module.cluster_role.aws_iam_role.this
}
moved {
  from = module.sg_eks[0].aws_iam_role_policy_attachment.cluster
  to   = module.sg_eks[0].module.cluster_role.aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
}
moved {
  from = module.sg_eks[0].aws_iam_role.node
  to   = module.sg_eks[0].module.node_role.aws_iam_role.this
}
moved {
  from = module.sg_eks[0].aws_iam_role_policy_attachment.node
  to   = module.sg_eks[0].module.node_role.aws_iam_role_policy_attachment.this
}
moved {
  from = module.sg_lbc[0].aws_iam_role.this
  to   = module.sg_lbc[0].module.role.aws_iam_role.this
}
moved {
  from = module.sg_lbc[0].aws_iam_role_policy_attachment.this
  to   = module.sg_lbc[0].module.role.aws_iam_role_policy_attachment.this["arn:aws:iam::620306387033:policy/AWSLoadBalancerControllerIAMPolicy"]
}
