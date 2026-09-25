output "container_app_id" {
  description = "Resource ID of the container app"
  value       = azurerm_container_app.main.id
}

output "container_app_name" {
  description = "Name of the container app"
  value       = azurerm_container_app.main.name
}

output "fqdn" {
  description = "Ingress FQDN of the latest revision"
  value       = azurerm_container_app.main.ingress[0].fqdn
}

output "latest_revision_name" {
  description = "Name of the latest revision"
  value       = azurerm_container_app.main.latest_revision_name
}
