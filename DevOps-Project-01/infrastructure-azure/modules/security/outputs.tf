output "gateway_nsg_id" {
  description = "ID of the Application Gateway NSG"
  value       = azurerm_network_security_group.gateway.id
}

output "app_nsg_id" {
  description = "ID of the application NSG"
  value       = azurerm_network_security_group.app.id
}

output "db_nsg_id" {
  description = "ID of the database NSG"
  value       = azurerm_network_security_group.db.id
}

output "bastion_nsg_id" {
  description = "ID of the bastion host NSG"
  value       = azurerm_network_security_group.bastion.id
}
