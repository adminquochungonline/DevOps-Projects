variable "name_prefix" {
  description = "Prefix for resource names (e.g. dev-django-app)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group holding the monitoring resources"
  type        = string
}

variable "retention_in_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email for the action group. Empty disables alerting."
  type        = string
  default     = ""
}

variable "container_app_id" {
  description = "Resource ID of the container app to watch. Empty during the platform-only phase."
  type        = string
  default     = ""
}

variable "alerts_enabled" {
  description = "Create the metric alert rules. Must be known at plan time (the container app exists only in the app phase)."
  type        = bool
  default     = false
}

variable "restart_count_threshold" {
  description = "Restarts within the alert window that trigger the crash-loop alert"
  type        = number
  default     = 3
}

variable "cpu_nanocores_threshold" {
  description = "Average CPU in nanocores that triggers the high-CPU alert (0.5 vCPU = 500000000)"
  type        = number
  default     = 400000000
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
