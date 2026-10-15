terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

resource "aws_sns_topic" "alerts" {
  count = var.manage ? 1 : 0
  name  = var.topic_name
  tags  = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.manage && var.manage_email_subscription ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_dashboard" "overview" {
  count          = var.manage ? 1 : 0
  dashboard_name = var.dashboard_name
  dashboard_body = var.dashboard_body
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = var.manage ? var.alarm_definitions : {}
  alarm_name          = each.key
  alarm_description   = each.value.alarm_description
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  treat_missing_data  = each.value.treat_missing_data
  dimensions          = each.value.dimensions
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = merge(var.tags, { Project = "aws-multi-region-dr-platform" })
}
