variable "global_cluster_identifier" { type = string }
variable "primary_cluster_identifier" { type = string }
variable "secondary_cluster_identifier" { type = string }
variable "engine" {
  type    = string
  default = "aurora-postgresql"
}
variable "engine_version" {
  type    = string
  default = "17.9"
}
variable "primary_region" { type = string }
variable "primary_subnet_group_name" { type = string }
variable "secondary_subnet_group_name" { type = string }
variable "primary_security_group_ids" {
  type    = list(string)
  default = []
}
variable "secondary_security_group_ids" {
  type    = list(string)
  default = []
}
variable "manage_clusters" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
