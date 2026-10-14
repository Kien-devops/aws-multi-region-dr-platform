variable "cluster_name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "oidc_issuer" { type = string }
variable "role_name" { type = string }
variable "policy_arn" { type = string }
variable "manage_helm" {
  type    = bool
  default = false
}
variable "chart_version" {
  type    = string
  default = "3.6.0"
}
variable "tags" {
  type    = map(string)
  default = {}
}
