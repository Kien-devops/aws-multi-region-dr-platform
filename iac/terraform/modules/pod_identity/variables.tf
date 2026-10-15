variable "cluster_name" { type = string }
variable "namespace" { type = string }
variable "service_account" { type = string }
variable "role_name" { type = string }
variable "policy_arns" { type = set(string) }
variable "description" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
