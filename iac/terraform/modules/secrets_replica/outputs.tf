output "arn" { value = try(aws_secretsmanager_secret.this[0].arn, null) }
