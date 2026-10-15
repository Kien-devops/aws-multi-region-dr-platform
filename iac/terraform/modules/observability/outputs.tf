output "topic_arn" { value = try(aws_sns_topic.alerts[0].arn, null) }
output "dashboard_arn" { value = try(aws_cloudwatch_dashboard.overview[0].dashboard_arn, null) }
