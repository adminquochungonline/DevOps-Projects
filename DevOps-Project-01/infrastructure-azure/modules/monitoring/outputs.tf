output "log_analytics_workspace_id" {
  description = "ID of the application Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.application.id
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = azurerm_monitor_action_group.main.id
}
