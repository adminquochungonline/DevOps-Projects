# Network Module
# Virtual Network with public (gateway) and private (application) subnets,
# NAT Gateway for outbound access from private subnets, a delegated subnet
# for MySQL Flexible Server, and NSG flow logging via Log Analytics.

resource "azurerm_virtual_network" "main" {
  name                = "${var.environment}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]

  tags = {
    Name        = "${var.environment}-vnet"
    Environment = var.environment
  }
}

# Public subnets (host the Application Gateway / bastion)
resource "azurerm_subnet" "public" {
  count                = length(var.public_subnets)
  name                 = "${var.environment}-public-subnet-${count.index + 1}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnets[count.index]]
}

# Private subnets (host the application VM scale set)
resource "azurerm_subnet" "private" {
  count                = length(var.private_subnets)
  name                 = "${var.environment}-private-subnet-${count.index + 1}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_subnets[count.index]]

  service_endpoints = ["Microsoft.Storage"]
}

# Delegated subnet dedicated to the MySQL Flexible Server (VNet integration).
# Carved from the VNet space; requires delegation to the DB service.
resource "azurerm_subnet" "database" {
  name                 = "${var.environment}-database-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 8, 10)]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Public IP for NAT Gateway (provides outbound connectivity for private subnets)
resource "azurerm_public_ip" "nat" {
  name                = "${var.environment}-nat-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Name        = "${var.environment}-nat-pip"
    Environment = var.environment
  }
}

resource "azurerm_nat_gateway" "main" {
  name                = "${var.environment}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"

  tags = {
    Name        = "${var.environment}-nat"
    Environment = var.environment
  }
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate the NAT Gateway with each private subnet for outbound traffic
resource "azurerm_subnet_nat_gateway_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = azurerm_subnet.private[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

# Private DNS zone required for MySQL Flexible Server VNet integration
resource "azurerm_private_dns_zone" "mysql" {
  name                = "${var.environment}.mysql.database.azure.com"
  resource_group_name = var.resource_group_name

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "${var.environment}-mysql-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

# Log Analytics workspace used as the destination for NSG flow logs
# (Azure equivalent of VPC Flow Logs -> CloudWatch).
resource "azurerm_log_analytics_workspace" "flow_logs" {
  name                = "${var.environment}-flow-logs-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = var.environment
  }
}
