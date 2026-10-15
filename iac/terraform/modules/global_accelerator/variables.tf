variable "name" { type = string }
variable "primary_endpoint_id" { type = string }
variable "secondary_endpoint_id" { type = string }
variable "primary_traffic_dial" {
  type    = number
  default = 100
}
variable "secondary_traffic_dial" {
  type    = number
  default = 0
}
variable "manage" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
