variable "topic_name" { type = string }
variable "alert_email" { type = string }
variable "dashboard_name" { type = string }
variable "dashboard_body" {
  type    = string
  default = "{\"widgets\":[]}"
}
variable "alarm_definitions" {
  type = map(object({
    alarm_description   = string
    comparison_operator = string
    evaluation_periods  = number
    metric_name         = string
    namespace           = string
    period              = number
    statistic           = string
    threshold           = number
    treat_missing_data  = optional(string, "missing")
    dimensions          = optional(map(string), {})
  }))
  default = {}
}
variable "manage" {
  type    = bool
  default = false
}
variable "manage_email_subscription" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
