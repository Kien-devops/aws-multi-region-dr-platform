variable "name" { type = string }
variable "description" {
  type    = string
  default = null
}
variable "assume_role_policy" { type = string }
variable "policy_arns" {
  type    = set(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
