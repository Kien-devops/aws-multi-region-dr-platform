provider "aws" {
  region = var.primary_region
  default_tags { tags = var.tags }
}

provider "aws" {
  alias  = "tokyo"
  region = var.secondary_region
  default_tags { tags = var.tags }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
