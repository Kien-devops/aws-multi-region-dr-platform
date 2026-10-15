variable "cluster_name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "oidc_issuer" { type = string }
variable "role_name" { type = string }
variable "role_description" {
  type    = string
  default = null
}
variable "policy_arn" { type = string }
variable "authentication_mode" {
  type    = string
  default = "pod_identity"
  validation {
    condition     = contains(["pod_identity", "irsa"], var.authentication_mode)
    error_message = "authentication_mode must be pod_identity or irsa."
  }
}
variable "manage_helm" {
  type    = bool
  default = false
}
variable "manage_service_account" {
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
