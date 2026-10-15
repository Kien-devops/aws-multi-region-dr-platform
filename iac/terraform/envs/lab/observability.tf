module "observability" {
  count                     = var.manage_observability ? 1 : 0
  source                    = "../../modules/observability"
  topic_name                = "dr-platform-alerts"
  alert_email               = var.alert_email
  dashboard_name            = "dr-platform-overview"
  dashboard_body            = var.observability_dashboard_body
  alarm_definitions         = var.observability_alarm_definitions
  manage                    = true
  manage_email_subscription = var.manage_alert_email_subscription
  tags                      = local.common_tags
}
