output "application_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "public_ip_address" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "backend_address_pool_ids" {
  description = "List of backend address pool IDs (for VMSS association)"
  value       = [for pool in azurerm_application_gateway.main.backend_address_pool : pool.id]
}
