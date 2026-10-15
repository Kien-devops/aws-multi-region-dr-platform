terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

resource "aws_eks_addon" "this" {
  for_each      = var.addon_names
  cluster_name  = var.cluster_name
  addon_name    = each.value
  addon_version = lookup(var.addon_versions, each.value, null)
  tags          = var.tags

  lifecycle {
    # Add-ons are imported; preserve the live conflict policy and tags.
    ignore_changes = [resolve_conflicts_on_update, tags]
  }
}
