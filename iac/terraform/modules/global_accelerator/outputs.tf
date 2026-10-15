output "accelerator_arn" { value = try(aws_globalaccelerator_accelerator.this[0].id, null) }
output "dns_name" { value = try(aws_globalaccelerator_accelerator.this[0].dns_name, null) }
