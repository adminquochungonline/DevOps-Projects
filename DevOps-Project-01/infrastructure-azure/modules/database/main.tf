# Database Module
# Azure Database for MySQL Flexible Server (replaces AWS RDS MySQL).
# Deployed with VNet integration into a delegated subnet, zone-redundant HA,
# encrypted storage and automated backups.

resource "azurerm_mysql_flexible_server" "main" {
  name                = "${var.environment}-mysql-server"
  location            = var.location
  resource_group_name = var.resource_group_name

  administrator_login    = var.db_username
  administrator_password = var.db_password

  # MySQL 8.0, general purpose, burstable SKU roughly matching db.t3.micro
  version  = "8.0.21"
  sku_name = "B_Standard_B1ms"

  # VNet integration: private access via delegated subnet + private DNS zone
  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  storage {
    size_gb           = 20
    auto_grow_enabled = true
  }

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # High availability across availability zones (Multi-AZ equivalent)
  high_availability {
    mode = "ZoneRedundant"
  }

  tags = {
    Name        = "${var.environment}-mysql-server"
    Environment = var.environment
  }
}

# Application database
resource "azurerm_mysql_flexible_database" "main" {
  name                = var.db_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# Enforce encrypted connections (TLS) between application and database
resource "azurerm_mysql_flexible_server_configuration" "require_secure_transport" {
  name                = "require_secure_transport"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "ON"
}
