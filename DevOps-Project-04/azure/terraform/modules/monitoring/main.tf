# Monitoring module - Azure equivalent of CloudWatch Logs + CloudWatch alarms.
# Container stdout/stderr is shipped here by the Container Apps environment, so
# no logging agent or sidecar is needed inside the image.

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

locals {
  # Whether to create the alert rules. Driven by a plan-time-known flag from the
  # root module: deriving it from container_app_id (unknown until apply) would
  # make `count` undeterminable at plan time.
  alerts_enabled = var.alerts_enabled && var.alert_email != ""
}

resource "azurerm_monitor_action_group" "main" {
  count = var.alert_email != "" ? 1 : 0

  name                = "${var.name_prefix}-ag"
  resource_group_name = var.resource_group_name
  short_name          = "dp04alerts"
  tags                = var.tags

  email_receiver {
    name                    = "ops"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Replicas restarting repeatedly usually means a crash loop: bad image, missing
# secret, or a failing liveness probe.
resource "azurerm_monitor_metric_alert" "restarts" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name_prefix}-restarts"
  resource_group_name = var.resource_group_name
  scopes              = [var.container_app_id]
  description         = "Container replicas are restarting repeatedly (possible crash loop)."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = var.restart_count_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
}

# Sustained high CPU means the autoscaler is at its ceiling or the replica is
# under-sized. Threshold is in nanocores: 0.5 vCPU = 500,000,000.
resource "azurerm_monitor_metric_alert" "cpu" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name_prefix}-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.container_app_id]
  description         = "Container CPU usage has been high for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "UsageNanoCores"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_nanocores_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
}
