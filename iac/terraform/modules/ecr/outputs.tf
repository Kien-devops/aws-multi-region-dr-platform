output "repository_arns" { value = { for k, v in aws_ecr_repository.this : k => v.arn } }
