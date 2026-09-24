# Database Module
# Azure Database for MySQL Flexible Server (replaces AWS RDS MySQL).
# Deployed with VNet integration into a delegated subnet, zone-redundant HA,
# encrypted storage and automated backups.

resource "azurerm_mysql_flexible_server" "main" {
  # Server name is a globally-unique public FQDN; suffix keeps it unique.
  name                = "${var.environment}-mysql-dp01hung"
  location            = var.location
  resource_group_name = var.resource_group_name

  administrator_login    = var.db_username
  administrator_password = var.db_password

  # MySQL 8.0. Burstable SKU (B_*) roughly matches db.t3.micro for dev.
  # NOTE: Burstable tier does NOT support zone-redundant HA; use a General
  # Purpose SKU (e.g. GP_Standard_D2ds_v4) if you enable high_availability.
  version  = var.mysql_version
  sku_name = var.sku_name

  # VNet integration: private access via delegated subnet + private DNS zone
  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  storage {
    size_gb           = 20
    auto_grow_enabled = true
  }

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # High availability across availability zones (Multi-AZ equivalent).
  # Only emitted when enabled, since Burstable SKUs reject HA outright.
  dynamic "high_availability" {
    for_each = var.high_availability_enabled ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  tags = {
    Name        = "${var.environment}-mysql-dp01hung"
    Environment = var.environment
  }

  # Azure assigns the availability zone at creation and it cannot be changed
  # afterwards. Ignore drift on zone (and the HA standby zone) so re-applies
  # don't attempt an illegal modification.
  lifecycle {
    ignore_changes = [
      zone,
      high_availability[0].standby_availability_zone,
    ]
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
