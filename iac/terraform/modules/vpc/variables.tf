variable "name" {
  type = string
}

variable "fsx_security_group_description" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "public_subnets" {
  type = map(string)
}

variable "private_subnets" {
  type = map(string)
}

variable "peer_cidr" {
  type = string
}

variable "peer_private_cidrs" {
  type = set(string)
}

variable "peer_id" {
  type     = string
  nullable = true
  default  = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
