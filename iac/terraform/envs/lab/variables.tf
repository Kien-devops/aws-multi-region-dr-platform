variable "account_id" { type = string }
variable "primary_region" {
  type    = string
  default = "ap-southeast-1"
}
variable "secondary_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "admin_principal_arn" { type = string }
variable "tags" {
  type    = map(string)
  default = { Environment = "lab" }
}
variable "create_network" {
  type    = bool
  default = false
}
variable "create_ecr" {
  type    = bool
  default = false
}
variable "create_eks" {
  type    = bool
  default = false
}
variable "create_lbc_role" {
  type    = bool
  default = false
}
variable "manage_lbc_helm" {
  type    = bool
  default = false
}
variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}
variable "kube_context" {
  type    = string
  default = ""
}
