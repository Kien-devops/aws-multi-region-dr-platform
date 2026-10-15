output "addon_arns" {
  value = { for name, addon in aws_eks_addon.this : name => addon.arn }
}
