output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "vnet_cidr_block" {
  description = "Address space of the Virtual Network"
  value       = azurerm_virtual_network.main.address_space[0]
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = azurerm_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = azurerm_subnet.private[*].id
}

output "database_subnet_id" {
  description = "ID of the delegated database subnet"
  value       = azurerm_subnet.database.id
}

output "mysql_private_dns_zone_id" {
  description = "ID of the private DNS zone for MySQL"
  value       = azurerm_private_dns_zone.mysql.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = azurerm_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway"
  value       = azurerm_public_ip.nat.ip_address
}

output "flow_logs_workspace_id" {
  description = "ID of the Log Analytics workspace for flow logs"
  value       = azurerm_log_analytics_workspace.flow_logs.id
}
