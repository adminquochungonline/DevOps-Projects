# Azure platform for DevOps-Project-06:
# sample-app runs as a Deployment on AKS, images live in ACR.
#
# Provisioned by azure/Jenkinsfile.infra.
# App deploy uses ACR to store images and deploys azure/k8s/*.yaml to AKS.

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Remote state on Azure Storage, same account/container as previous projects,
  # but with its own key for DevOps-Project-06.
  # storage_account_name comes from -backend-config.
  backend "azurerm" {
    resource_group_name = "tfstate-rg"
    container_name      = "tfstate"
    key                 = "devops-project-06/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {
  name_prefix = "${var.environment}-sampleapp"

  # Naming convention shared with app pipeline
  registry_name = "${var.environment}sampleapp${var.name_suffix}"
  cluster_name  = "${local.name_prefix}-aks"

  common_tags = {
    Environment = var.environment
    Project     = "DevOps-Project-06"
    Workload    = "sampleapp"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

# Private image registry
resource "azurerm_container_registry" "main" {
  name                = local.registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = true
  tags                = local.common_tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.environment}sampleapp${var.name_suffix}"
  node_resource_group = "${local.name_prefix}-aks-nodes-rg"

  # null = AKS default version for the region.
  kubernetes_version = var.kubernetes_version != "" ? var.kubernetes_version : null
  sku_tier           = var.aks_sku_tier

  # Kubernetes RBAC on
  role_based_access_control_enabled = true

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = var.node_count
    os_disk_size_gb             = var.node_os_disk_size_gb
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "10%"
    }

    tags = local.common_tags
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
  }

  tags = local.common_tags
}

# Lets the kubelet identity pull from the registry.
resource "azurerm_role_assignment" "aks_acr_pull" {
  count = var.manage_acr_pull_assignment ? 1 : 0

  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
