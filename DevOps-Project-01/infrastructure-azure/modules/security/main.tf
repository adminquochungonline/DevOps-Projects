# Security Module
# Network Security Groups replacing AWS Security Groups.
# Azure NSGs are stateful and are attached to subnets or NICs. Rules use
# priority ordering and named service tags instead of referencing peer SGs.

# Application Gateway NSG (public tier) - allows inbound HTTP/HTTPS from Internet
resource "azurerm_network_security_group" "gateway" {
  name                = "${var.environment}-gateway-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Application Gateway v2 requires the Gateway Manager infrastructure ports
  security_rule {
    name                       = "AllowGatewayManager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  tags = {
    Name        = "${var.environment}-gateway-nsg"
    Environment = var.environment
  }
}

# Application tier NSG - allows traffic from the gateway subnet and SSH from bastion
resource "azurerm_network_security_group" "app" {
  name                = "${var.environment}-app-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Allow application traffic (Tomcat on 8080) from the public/gateway subnets
  security_rule {
    name                       = "AllowAppFromGateway"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Allow SSH from within the VNet (bastion host sits in the public subnet)
  security_rule {
    name                       = "AllowSSHFromBastion"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  tags = {
    Name        = "${var.environment}-app-nsg"
    Environment = var.environment
  }
}

# Database tier NSG - allows MySQL (3306) only from the application subnet range
resource "azurerm_network_security_group" "db" {
  name                = "${var.environment}-db-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowMySQLFromApp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Name        = "${var.environment}-db-nsg"
    Environment = var.environment
  }
}

# Bastion host NSG - allows SSH from approved source ranges only
resource "azurerm_network_security_group" "bastion" {
  name                = "${var.environment}-bastion-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "security_rule" {
    for_each = var.allowed_ssh_source_ranges
    content {
      name                       = "AllowSSH-${security_rule.key}"
      priority                   = 100 + security_rule.key
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }

  tags = {
    Name        = "${var.environment}-bastion-nsg"
    Environment = var.environment
  }
}
