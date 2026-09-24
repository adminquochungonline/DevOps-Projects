# Main Terraform configuration for Azure infrastructure
# 3-tier Java application deployment on Microsoft Azure

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Remote state on Azure Storage. The storage account/container must exist
  # before `terraform init`. Values (esp. storage_account_name) are provided at
  # init time via -backend-config in the pipeline, so they are not hardcoded.
  backend "azurerm" {
    resource_group_name = "tfstate-rg"
    container_name      = "tfstate"
    key                 = "java-app/terraform.tfstate"
    # storage_account_name is passed via -backend-config in Jenkinsfile.infra
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Resource Group holding all resources for this environment
resource "azurerm_resource_group" "main" {
  name     = "${var.environment}-java-app-rg"
  location = var.location

  tags = {
    Environment = var.environment
    Project     = "java-login-app"
  }
}

# Networking Module (VNet, subnets, NAT gateway, flow logs)
module "network" {
  source = "./modules/network"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  vnet_cidr           = var.vnet_cidr
  public_subnets      = var.public_subnets
  private_subnets     = var.private_subnets
}

# Security Module (Network Security Groups)
module "security" {
  source = "./modules/security"

  environment               = var.environment
  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  allowed_ssh_source_ranges = var.allowed_ssh_source_ranges
}

# Database Module (Azure Database for MySQL Flexible Server)
module "database" {
  source = "./modules/database"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  delegated_subnet_id = module.network.database_subnet_id
  private_dns_zone_id = module.network.mysql_private_dns_zone_id
  db_name             = var.db_name
  db_username         = var.db_username
  db_password         = var.db_password

  sku_name                  = var.db_sku_name
  mysql_version             = var.db_version
  high_availability_enabled = var.db_high_availability_enabled

  # The Flexible Server requires the VNet-to-private-DNS-zone link to exist and
  # propagate before creation. Referencing only the zone ID creates a dependency
  # on the zone (fast) but not the link (~1 min), causing the intermittent
  # VnetNotLinkedToPrivateDnsZone failure. Wait for the whole network module.
  depends_on = [module.network]
}

# Application Gateway Module (replaces AWS ALB)
module "appgw" {
  source = "./modules/appgw"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  public_subnet_id    = module.network.public_subnet_ids[0]
}

# Virtual Machine Scale Set Module (replaces AWS ASG)
module "vmss" {
  source = "./modules/vmss"

  environment               = var.environment
  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  private_subnet_id         = module.network.private_subnet_ids[0]
  network_security_group_id = module.security.app_nsg_id
  backend_address_pool_ids  = module.appgw.backend_address_pool_ids
  vm_size                   = var.vm_size
  admin_username            = var.admin_username
  admin_ssh_public_key      = var.admin_ssh_public_key
  instances                 = var.vmss_instances
  min_instances             = var.vmss_min_instances
  max_instances             = var.vmss_max_instances
  # App WAR + DB config are applied by the app pipeline via az vmss run-command,
  # not baked into the scale set, so nothing app-specific is passed here.
}

# Monitoring Module (Log Analytics + Azure Monitor alerts)
module "monitoring" {
  source = "./modules/monitoring"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  mysql_server_id     = module.database.mysql_server_id
  vmss_id             = module.vmss.vmss_id
}
