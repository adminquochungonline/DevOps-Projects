# Container Registry module - Azure equivalent of Amazon ECR.
# Authentication is RBAC + managed identity only: the shared admin account stays
# disabled so there is no registry password to rotate or leak.

resource "azurerm_container_registry" "main" {
  name                = var.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false
  tags                = var.tags

  # Auto-deleting untagged manifests is the closest equivalent to an ECR
  # lifecycle policy. Premium-only, so the block is omitted on Basic/Standard.
  dynamic "retention_policy" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      days    = var.untagged_retention_days
      enabled = true
    }
  }

  # Vulnerability scanning on push is provided by Microsoft Defender for
  # Containers (subscription-level setting), not by the registry resource.
}

# Pull permission for the container app workload identity (least privilege).
# Keyed by a static label, not by the principal ID: the identity is created in
# the same run, so its principal ID is unknown at plan time and cannot be used
# as a for_each key.
resource "azurerm_role_assignment" "acr_pull" {
  for_each = var.pull_principals

  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = each.value
  # Avoids "principal not found" races right after the identity is created.
  skip_service_principal_aad_check = true
}

# Push permission for the CI service principal (optional: skip when the SP is
# already Contributor on the subscription).
resource "azurerm_role_assignment" "acr_push" {
  count = var.push_principal_id != "" ? 1 : 0

  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPush"
  principal_id                     = var.push_principal_id
  skip_service_principal_aad_check = true
}
