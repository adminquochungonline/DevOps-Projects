# Azure platform for DevOps-Project-05: the regapp WAR runs as a Deployment on
# AKS (the project ships Kubernetes manifests), images live in ACR.
#
# Provisioned by azure/Jenkinsfile.infra. azure/Jenkinsfile.app only builds the
# image (az acr build) and applies azure/k8s/*.yaml with kubectl; it never
# touches this state, so app deploys cannot drift the infrastructure.

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Remote state on Azure Storage, same account/container as DevOps-Project-01
  # and -04 but its own key. storage_account_name comes from -backend-config.
  backend "azurerm" {
    resource_group_name = "tfstate-rg"
    container_name      = "tfstate"
    key                 = "regapp-aks/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      # AKS creates the LoadBalancer public IP in its node resource group, not
      # here, but keep destroy unblocked if anything is added by hand.
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {
  name_prefix = "${var.environment}-regapp"

  # Naming convention shared with Jenkinsfile.app, which derives these names
  # instead of reading Terraform state.
  registry_name = "${var.environment}regapp${var.name_suffix}"
  cluster_name  = "${local.name_prefix}-aks"

  common_tags = {
    Environment = var.environment
    Project     = "DevOps-Project-05"
    Workload    = "regapp"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

# Private image registry (replaces the public valaxy/regapp Docker Hub image).
# Admin user disabled: AKS pulls with its kubelet managed identity + AcrPull.
resource "azurerm_container_registry" "main" {
  name                = local.registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.common_tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.environment}regapp${var.name_suffix}"
  node_resource_group = "${local.name_prefix}-aks-nodes-rg"

  # null = AKS default version for the region.
  kubernetes_version = var.kubernetes_version != "" ? var.kubernetes_version : null
  sku_tier           = var.aks_sku_tier

  # Kubernetes RBAC on; local accounts kept so the pipeline can use
  # `az aks get-credentials` without Entra ID / kubelogin.
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

  # Azure CNI Overlay: pods get IPs from a private overlay range, so no VNet
  # address planning is needed (kubenet is being retired).
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
  }

  tags = local.common_tags
}

# Lets the kubelet identity pull from the registry. Creating a role assignment
# needs Microsoft.Authorization/roleAssignments/write on the pipeline SP (the
# same "RBAC Administrator constrained to AcrPull" grant as DevOps-Project-04).
# Set manage_acr_pull_assignment = false and grant by hand if the SP is
# Contributor-only (see the acr_pull_grant_command output).
resource "azurerm_role_assignment" "aks_acr_pull" {
  count = var.manage_acr_pull_assignment ? 1 : 0

  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
