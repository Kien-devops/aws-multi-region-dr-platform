variable "cluster_name" { type = string }

variable "addon_names" {
  type    = set(string)
  default = ["eks-pod-identity-agent", "amazon-cloudwatch-observability"]
}

variable "addon_versions" {
  type    = map(string)
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
