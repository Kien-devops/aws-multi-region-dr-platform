variable "account_id" {
  type        = string
  description = "AWS account ID used for stable IAM ARNs."
}
variable "primary_region" {
  type    = string
  default = "ap-southeast-1"
}
variable "secondary_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "admin_principal_arn" { type = string }
variable "sg_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}
variable "tokyo_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "sg_availability_zones" {
  type    = list(string)
  default = ["ap-southeast-1a", "ap-southeast-1b"]
}
variable "tokyo_availability_zones" {
  type    = list(string)
  default = ["ap-northeast-1a", "ap-northeast-1c"]
}
variable "sg_public_subnets" {
  type    = map(string)
  default = { "ap-southeast-1a" = "10.10.1.0/24", "ap-southeast-1b" = "10.10.2.0/24" }
}
variable "sg_private_subnets" {
  type    = map(string)
  default = { "ap-southeast-1a" = "10.10.11.0/24", "ap-southeast-1b" = "10.10.12.0/24" }
}
variable "tokyo_public_subnets" {
  type    = map(string)
  default = { "ap-northeast-1a" = "10.20.1.0/24", "ap-northeast-1c" = "10.20.2.0/24" }
}
variable "tokyo_private_subnets" {
  type    = map(string)
  default = { "ap-northeast-1a" = "10.20.11.0/24", "ap-northeast-1c" = "10.20.12.0/24" }
}
variable "ecr_repository_names" {
  type    = set(string)
  default = ["app2-frontend", "app2-backend-1", "app2-backend-2", "app2-backend-3", "app2-file-service"]
}
variable "sg_oidc_issuer" {
  type    = string
  default = ""
}
variable "aurora_global_cluster_identifier" {
  type    = string
  default = "app2-global-db"
}
variable "aurora_primary_cluster_identifier" {
  type    = string
  default = "app2-sg-db"
}
variable "aurora_secondary_cluster_identifier" {
  type    = string
  default = "app2-global-db-cluster-1"
}
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
variable "create_tokyo_eks" {
  type    = bool
  default = false
}
variable "create_lbc_role" {
  type    = bool
  default = false
}
variable "create_tokyo_lbc_role" {
  type    = bool
  default = false
}
variable "tokyo_oidc_issuer" {
  type    = string
  default = ""
}
variable "manage_lbc_helm" {
  type    = bool
  default = false
}
variable "manage_lbc_service_account" {
  type    = bool
  default = false
}
variable "manage_platform_pod_identity" {
  type    = bool
  default = false
}
variable "lbc_authentication_mode" {
  type    = string
  default = "pod_identity"
  validation {
    condition     = contains(["irsa", "pod_identity"], var.lbc_authentication_mode)
    error_message = "lbc_authentication_mode must be irsa or pod_identity."
  }
}
variable "manage_eks_addons" {
  type    = bool
  default = false
}
variable "manage_tokyo_eks_addons" {
  type    = bool
  default = false
}
variable "manage_aurora" {
  type    = bool
  default = false
}
variable "manage_secret_replication" {
  type    = bool
  default = false
}
variable "manage_global_accelerator" {
  type    = bool
  default = false
}
variable "manage_aurora_clusters" {
  type    = bool
  default = false
}
variable "manage_observability" {
  type    = bool
  default = false
}
variable "manage_alert_email_subscription" {
  type    = bool
  default = false
}
variable "observability_dashboard_body" {
  type    = string
  default = "{\"widgets\":[]}"
}
variable "observability_alarm_definitions" {
  type = map(object({
    alarm_description   = string
    comparison_operator = string
    evaluation_periods  = number
    metric_name         = string
    namespace           = string
    period              = number
    statistic           = string
    threshold           = number
    treat_missing_data  = optional(string, "missing")
    dimensions          = optional(map(string), {})
  }))
  default = {}
}
variable "global_accelerator_primary_endpoint_id" {
  type     = string
  nullable = true
  default  = null
}
variable "global_accelerator_secondary_endpoint_id" {
  type     = string
  nullable = true
  default  = null
}
variable "aurora_primary_subnet_group_name" {
  type    = string
  default = "app2-sg-db-subnet-group"
}
variable "aurora_secondary_subnet_group_name" {
  type    = string
  default = "app2-tokyo-db-subnet-group"
}
variable "secret_name" {
  type    = string
  default = "/app2/database"
}
variable "alert_email" {
  type    = string
  default = "24520885@gm.uit.edu.vn"
}
variable "node_min_size" {
  type    = number
  default = 0
}
variable "node_max_size" {
  type    = number
  default = 4
}
variable "node_desired_size" {
  type    = number
  default = 0
}
variable "sg_node_desired_size" {
  type    = number
  default = 0
}
variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}
variable "kube_context" {
  type    = string
  default = ""
}
