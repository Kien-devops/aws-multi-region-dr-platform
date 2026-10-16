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
variable "primary_instance_identifier" { type = string }
variable "secondary_instance_identifier" { type = string }
variable "primary_instance_class" { type = string }
variable "secondary_instance_class" { type = string }
variable "primary_availability_zone" { type = string }
variable "secondary_availability_zone" { type = string }
variable "primary_kms_key_id" { type = string }
variable "secondary_kms_key_id" { type = string }
variable "primary_backup_window" { type = string }
variable "secondary_backup_window" { type = string }
variable "primary_maintenance_window" { type = string }
variable "secondary_maintenance_window" { type = string }
variable "primary_monitoring_role_arn" { type = string }
variable "secondary_monitoring_role_arn" { type = string }
variable "manage_clusters" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
