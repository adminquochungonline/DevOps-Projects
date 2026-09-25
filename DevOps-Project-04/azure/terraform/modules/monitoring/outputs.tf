output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "action_group_id" {
  description = "Resource ID of the alert action group (empty when alerting is disabled)"
  value       = var.alert_email != "" ? azurerm_monitor_action_group.main[0].id : ""
}
