output "state_machine_arn" { value = aws_sfn_state_machine.this.arn }
output "event_rule_arn" { value = try(aws_cloudwatch_event_rule.alarm[0].arn, null) }
output "lock_table_name" { value = aws_dynamodb_table.lock.name }
output "approval_table_name" { value = aws_dynamodb_table.approval.name }
output "notification_topic_arn" { value = aws_sns_topic.notifications.arn }
output "lambda_arns" { value = { for k, f in aws_lambda_function.this : k => f.arn } }
output "approval_callback_lambda_arn" { value = aws_lambda_function.this["approval_callback"].arn }
output "approval_api_url" { value = aws_apigatewayv2_api.approval.api_endpoint }
