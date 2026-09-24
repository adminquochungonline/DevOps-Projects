output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = module.network.vnet_id
}

output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = module.appgw.public_ip_address
}

output "mysql_server_fqdn" {
  description = "Fully qualified domain name of the MySQL server"
  value       = module.database.mysql_server_fqdn
}

output "vmss_id" {
  description = "ID of the Virtual Machine Scale Set"
  value       = module.vmss.vmss_id
}
