# Main Terraform configuration for the Azure deployment of DevOps-Project-04.
# Django container on Azure Container Apps (the Azure counterpart of ECS Fargate).
#
# Two-phase by design, driven by var.container_image:
#   phase 1 (Jenkinsfile.infra, container_image = "")  -> registry, logs,
#            identity and Container Apps environment only
#   phase 2 (Jenkinsfile.app, container_image = "...") -> the container app
#            itself, one new revision per image tag
# The registry cannot hold an image before it exists, so the app must come second.

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Remote state on Azure Storage, same account/container as DevOps-Project-01
  # but a different key, so the two projects never share state.
  # storage_account_name is supplied at init time via -backend-config.
  backend "azurerm" {
    resource_group_name = "tfstate-rg"
    container_name      = "tfstate"
    key                 = "django-app/terraform.tfstate"
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
  name_prefix = "${var.environment}-django-app"

  # Empty image = platform-only apply (see the header comment).
  deploy_app = var.container_image != ""

  common_tags = {
    Environment = var.environment
    Project     = "DevOps-Project-04"
    Workload    = "django-hello-world"
    ManagedBy   = "terraform"
  }
}

# Resource Group holding all resources for this environment
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

# Workload identity used by the container app to pull from the registry.
# Replaces the AWS ecsTaskExecutionRole; no registry password anywhere.
resource "azurerm_user_assigned_identity" "app" {
  name                = "${local.name_prefix}-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Container Registry Module (replaces AWS ECR)
module "registry" {
  source = "./modules/registry"

  location                = var.location
  resource_group_name     = azurerm_resource_group.main.name
  registry_name           = "${var.environment}django${var.name_suffix}"
  sku                     = var.acr_sku
  untagged_retention_days = var.acr_untagged_retention_days

  # Pull side: the container app identity. Push side: the CI service principal.
  pull_principals   = { container_app = azurerm_user_assigned_identity.app.principal_id }
  push_principal_id = var.cicd_principal_id

  tags = local.common_tags
}

# Monitoring Module (Log Analytics + Azure Monitor alerts; replaces CloudWatch)
module "monitoring" {
  source = "./modules/monitoring"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  retention_in_days   = var.log_retention_in_days
  alert_email         = var.alert_email

  # Alerts scope onto the app, so they only exist in the app phase.
  alerts_enabled   = local.deploy_app
  container_app_id = local.deploy_app ? module.container_app[0].container_app_id : ""

  tags = local.common_tags
}

# Container Apps Module (replaces ECS cluster + task definition + service + ALB)
module "container_app" {
  source = "./modules/container_app"
  count  = local.deploy_app ? 1 : 0

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  container_app_environment_id = azurerm_container_app_environment.main.id
  managed_identity_id          = azurerm_user_assigned_identity.app.id
  registry_login_server        = module.registry.login_server
  container_image              = var.container_image

  django_secret_key    = var.django_secret_key
  allowed_hosts        = var.allowed_hosts
  csrf_trusted_origins = var.csrf_trusted_origins

  target_port         = var.target_port
  cpu                 = var.container_cpu
  memory              = var.container_memory
  min_replicas        = var.min_replicas
  max_replicas        = var.max_replicas
  concurrent_requests = var.concurrent_requests
  external_ingress    = var.external_ingress

  tags = local.common_tags

  # AcrPull must be in place before the first revision tries to pull.
  depends_on = [module.registry]
}

# Container Apps environment: the shared compute/networking boundary for the
# app, equivalent to an ECS cluster. Kept in the root module because both the
# platform phase and the app phase reference it.
resource "azurerm_container_app_environment" "main" {
  name                       = "${local.name_prefix}-env"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.common_tags
}
