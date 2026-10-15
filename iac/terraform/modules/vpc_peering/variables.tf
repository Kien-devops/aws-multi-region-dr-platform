variable "requester_vpc_id" { type = string }
variable "accepter_vpc_id" { type = string }
variable "peer_region" { type = string }
variable "requester_private_route_table_id" { type = string }
variable "accepter_private_route_table_id" { type = string }
variable "requester_route_cidr" { type = string }
variable "accepter_route_cidr" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
