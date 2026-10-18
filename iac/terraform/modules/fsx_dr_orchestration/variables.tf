variable "name_prefix" {
  type    = string
  default = "dr-fsx-failover"
}
variable "region" { type = string }
variable "vpc_id" {
  type     = string
  default  = null
  nullable = true
}
variable "alarm_names" {
  type    = set(string)
  default = []
}
variable "lock_table_name" {
  type    = string
  default = "dr-fsx-failover-lock"
}
variable "approval_table_name" {
  type    = string
  default = "dr-fsx-failover-approvals"
}
variable "notification_topic_name" {
  type    = string
  default = "dr-fsx-failover-notifications"
}
variable "ontap_management_secret_arn" {
  type     = string
  default  = null
  nullable = true
}
variable "gitops_secret_arn" {
  type     = string
  default  = null
  nullable = true
}
variable "file_service_url" {
  type    = string
  default = ""
}
variable "traffic_endpoint_group_arns" {
  type    = set(string)
  default = []
}
variable "vpc_subnet_ids" {
  type    = list(string)
  default = []
}
variable "security_group_ids" {
  type    = list(string)
  default = []
}
variable "source_path" {
  type    = string
  default = "dr-sg-svm:drdata"
}
variable "destination_path" {
  type    = string
  default = "dr-tokyo-svm:dr_data_dr"
}
variable "enable_event_trigger" {
  type    = bool
  default = false
}
variable "enable_promotion" {
  type    = bool
  default = false
}
variable "enable_traffic_switch" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
