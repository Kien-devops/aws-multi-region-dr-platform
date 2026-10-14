variable "repository_names" {
  type = set(string)
}

variable "destination_region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
