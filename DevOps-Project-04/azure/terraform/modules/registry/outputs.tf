output "registry_id" {
  description = "Resource ID of the container registry"
  value       = azurerm_container_registry.main.id
}

output "registry_name" {
  description = "Name of the container registry"
  value       = azurerm_container_registry.main.name
}

output "login_server" {
  description = "Login server, e.g. devdjangodp04hung.azurecr.io"
  value       = azurerm_container_registry.main.login_server
}
