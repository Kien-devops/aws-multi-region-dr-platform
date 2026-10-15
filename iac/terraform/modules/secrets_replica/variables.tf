variable "name" { type = string }
variable "replica_region" { type = string }
variable "description" {
  type    = string
  default = ""
}
variable "manage_secret" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
