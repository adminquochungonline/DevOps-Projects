output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "registry_name" {
  description = "Container Registry name (used by 'az acr build' in the app pipeline)"
  value       = module.registry.registry_name
}

output "registry_login_server" {
  description = "Container Registry login server"
  value       = module.registry.login_server
}

output "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace collecting container logs"
  value       = module.monitoring.log_analytics_workspace_name
}

output "managed_identity_client_id" {
  description = "Client ID of the workload identity used for registry pulls"
  value       = azurerm_user_assigned_identity.app.client_id
}

output "managed_identity_principal_id" {
  description = "Principal (object) ID of the workload identity. Use it to grant AcrPull by hand when manage_acr_pull_assignment = false."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "acr_pull_grant_command" {
  description = "Ready-to-run command that grants AcrPull out-of-band. Empty when Terraform manages the assignment itself."
  value = var.manage_acr_pull_assignment ? "" : join(" ", [
    "az role assignment create",
    "--assignee-object-id ${azurerm_user_assigned_identity.app.principal_id}",
    "--assignee-principal-type ServicePrincipal",
    "--role AcrPull",
    "--scope ${module.registry.registry_id}",
  ])
}

output "container_app_name" {
  description = "Name of the container app (empty until an image is deployed)"
  value       = local.deploy_app ? module.container_app[0].container_app_name : ""
}

output "app_fqdn" {
  description = "Ingress FQDN of the container app (empty until an image is deployed)"
  value       = local.deploy_app ? module.container_app[0].fqdn : ""
}

output "app_url" {
  description = "Public URL of the container app (empty until an image is deployed)"
  value       = local.deploy_app ? "https://${module.container_app[0].fqdn}" : ""
}
