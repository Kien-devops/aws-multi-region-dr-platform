terraform {
  required_providers {
    aws     = { source = "hashicorp/aws" }
    archive = { source = "hashicorp/archive" }
  }
}

locals {
  tags = merge(var.tags, { Component = "fsx-dr-orchestration" })
  lambda_names = {
    validate          = "validate-event"
    lock              = "lock"
    failure           = "verify-failure"
    approval          = "request-approval"
    approval_callback = "approval-callback"
    fencing           = "verify-fencing"
    snapmirror        = "snapmirror"
    promotion         = "promote-tokyo"
    promotion_verify  = "verify-promotion"
    storage           = "prepare-storage"
    gitops            = "update-gitops"
    file_verify       = "verify-file-service"
    traffic           = "switch-traffic"
    notify            = "notify"
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/handlers.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockName"
  attribute {
    name = "LockName"
    type = "S"
  }
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
  tags = local.tags
}

resource "aws_dynamodb_table" "approval" {
  name         = var.approval_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ApprovalId"
  attribute {
    name = "ApprovalId"
    type = "S"
  }
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
  tags = local.tags
}

resource "aws_sns_topic" "notifications" {
  name = var.notification_topic_name
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "state_machine" {
  name              = "/aws/vendedlogs/states/${var.name_prefix}"
  retention_in_days = 30
  tags              = local.tags
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count      = length(var.vpc_subnet_ids) > 0 ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "lambda_runtime" {
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.lock.arn, aws_dynamodb_table.approval.arn]
  }
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }
  dynamic "statement" {
    for_each = length(compact([var.ontap_management_secret_arn, var.gitops_secret_arn])) > 0 ? [1] : []
    content {
      actions   = ["secretsmanager:GetSecretValue"]
      resources = compact([var.ontap_management_secret_arn, var.gitops_secret_arn])
    }
  }
  statement {
    actions   = ["states:SendTaskSuccess", "states:SendTaskFailure"]
    resources = ["*"]
  }
  dynamic "statement" {
    for_each = length(var.traffic_endpoint_group_arns) > 0 ? [1] : []
    content {
      actions   = ["globalaccelerator:DescribeEndpointGroup", "globalaccelerator:UpdateEndpointGroup"]
      resources = var.traffic_endpoint_group_arns
    }
  }
}

resource "aws_iam_role_policy" "lambda_runtime" {
  name   = "${var.name_prefix}-lambda-runtime"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_runtime.json
}

resource "aws_security_group" "lambda" {
  count       = var.vpc_id != null && length(var.vpc_subnet_ids) > 0 ? 1 : 0
  name_prefix = "${var.name_prefix}-lambda-"
  description = "Egress-only security group for FSx DR orchestration Lambda"
  vpc_id      = var.vpc_id
  egress {
    description = "Private AWS service and ONTAP API access"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.lambda_names
  name              = "/aws/lambda/${var.name_prefix}-${each.value}"
  retention_in_days = 30
  tags              = local.tags
}

resource "aws_lambda_function" "this" {
  for_each         = local.lambda_names
  function_name    = "${var.name_prefix}-${each.value}"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "handlers.lambda_handler"
  runtime          = "python3.12"
  timeout          = each.key == "approval" ? 30 : 60
  memory_size      = 256
  architectures    = ["x86_64"]
  environment {
    variables = {
      LOCK_TABLE_NAME             = aws_dynamodb_table.lock.name
      APPROVAL_TABLE_NAME         = aws_dynamodb_table.approval.name
      NOTIFICATION_TOPIC_ARN      = aws_sns_topic.notifications.arn
      ONTAP_SECRET_ARN            = var.ontap_management_secret_arn != null ? var.ontap_management_secret_arn : ""
      GITOPS_SECRET_ARN           = var.gitops_secret_arn != null ? var.gitops_secret_arn : ""
      FILE_SERVICE_URL            = var.file_service_url
      SOURCE_PATH                 = var.source_path
      DESTINATION_PATH            = var.destination_path
      ENABLE_PROMOTION            = tostring(var.enable_promotion)
      ENABLE_TRAFFIC_SWITCH       = tostring(var.enable_traffic_switch)
      TRAFFIC_ENDPOINT_GROUP_ARNS = join(",", var.traffic_endpoint_group_arns)
      FUNCTION_NAME               = each.key
    }
  }
  dynamic "vpc_config" {
    for_each = length(var.vpc_subnet_ids) > 0 && (length(var.security_group_ids) > 0 || length(aws_security_group.lambda) > 0) ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.lambda[0].id]
    }
  }
  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.lambda]
}

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.name_prefix}-states"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "sfn_runtime" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [for f in aws_lambda_function.this : f.arn]
  }
  statement {
    actions   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sfn_runtime" {
  name   = "${var.name_prefix}-states-runtime"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn_runtime.json
}

resource "aws_sfn_state_machine" "this" {
  name     = "${var.name_prefix}-state-machine"
  role_arn = aws_iam_role.sfn.arn
  definition = templatefile("${path.module}/state_machine.asl.json.tftpl", {
    validate_arn         = aws_lambda_function.this["validate"].arn
    lock_arn             = aws_lambda_function.this["lock"].arn
    failure_arn          = aws_lambda_function.this["failure"].arn
    approval_arn         = aws_lambda_function.this["approval"].arn
    fencing_arn          = aws_lambda_function.this["fencing"].arn
    snapmirror_arn       = aws_lambda_function.this["snapmirror"].arn
    promotion_arn        = aws_lambda_function.this["promotion"].arn
    promotion_verify_arn = aws_lambda_function.this["promotion_verify"].arn
    storage_arn          = aws_lambda_function.this["storage"].arn
    gitops_arn           = aws_lambda_function.this["gitops"].arn
    file_verify_arn      = aws_lambda_function.this["file_verify"].arn
    traffic_arn          = aws_lambda_function.this["traffic"].arn
    notify_arn           = aws_lambda_function.this["notify"].arn
    release_arn          = aws_lambda_function.this["lock"].arn
  })
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.state_machine.arn}:*"
    include_execution_data = false
    level                  = "ALL"
  }
  tags = local.tags
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events" {
  name               = "${var.name_prefix}-events"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "events" {
  name   = "${var.name_prefix}-events-start-execution"
  role   = aws_iam_role.events.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "states:StartExecution", Resource = aws_sfn_state_machine.this.arn }] })
}

resource "aws_cloudwatch_event_rule" "alarm" {
  count       = var.enable_event_trigger ? 1 : 0
  name        = "${var.name_prefix}-event-rule"
  description = "Starts the gated FSx DR workflow after a configured CloudWatch alarm enters ALARM."
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"],
    detail-type = ["CloudWatch Alarm State Change"],
    detail      = merge({ state = { value = ["ALARM"] } }, length(var.alarm_names) > 0 ? { alarmName = var.alarm_names } : {})
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "state_machine" {
  count    = var.enable_event_trigger ? 1 : 0
  rule     = aws_cloudwatch_event_rule.alarm[0].name
  arn      = aws_sfn_state_machine.this.arn
  role_arn = aws_iam_role.events.arn
  input_transformer {
    input_paths    = { alarm = "$.detail", event_id = "$.id", time = "$.time" }
    input_template = "{\"eventType\":\"cloudwatch-alarm\",\"alarm\":<alarm>,\"eventId\":<event_id>,\"failureStartedAt\":<time>,\"dryRun\":false}"
  }
}

resource "aws_apigatewayv2_api" "approval" {
  name          = "${var.name_prefix}-approval"
  protocol_type = "HTTP"
  tags          = local.tags
}

resource "aws_apigatewayv2_stage" "approval" {
  api_id      = aws_apigatewayv2_api.approval.id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags
}

resource "aws_apigatewayv2_route" "approval" {
  api_id             = aws_apigatewayv2_api.approval.id
  route_key          = "POST /approval"
  target             = "integrations/${aws_apigatewayv2_integration.approval.id}"
  authorization_type = "AWS_IAM"
}

resource "aws_apigatewayv2_integration" "approval" {
  api_id                 = aws_apigatewayv2_api.approval.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this["approval_callback"].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "approval_api" {
  statement_id  = "AllowApprovalApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["approval_callback"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.approval.execution_arn}/*/*"
}

