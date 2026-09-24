# Monitoring Module
# Azure Monitor equivalents of the AWS CloudWatch log group + metric alarms.
# Log Analytics workspace collects application logs; metric alerts watch MySQL
# and the VM Scale Set for high CPU / low memory conditions.

# Log Analytics workspace for application logs (replaces CloudWatch Log Group)
resource "azurerm_log_analytics_workspace" "application" {
  name                = "${var.environment}-application-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Name        = "${var.environment}-application-logs"
    Environment = var.environment
  }
}

# Action group (target for alerts; empty by default, add receivers as needed)
resource "azurerm_monitor_action_group" "main" {
  name                = "${var.environment}-alerts-ag"
  resource_group_name = var.resource_group_name
  short_name          = "alerts"

  tags = {
    Environment = var.environment
  }
}

# MySQL high CPU alert (replaces RDS CPUUtilization alarm > 80%)
resource "azurerm_monitor_metric_alert" "mysql_cpu" {
  name                = "${var.environment}-mysql-high-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.mysql_server_id]
  description         = "Alerts when MySQL CPU utilization exceeds 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = {
    Name        = "${var.environment}-mysql-cpu-alarm"
    Environment = var.environment
  }
}

# MySQL low available memory alert (replaces RDS FreeableMemory alarm < 256MB)
resource "azurerm_monitor_metric_alert" "mysql_memory" {
  name                = "${var.environment}-mysql-low-memory"
  resource_group_name = var.resource_group_name
  scopes              = [var.mysql_server_id]
  description         = "Alerts when MySQL memory usage exceeds 90%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "memory_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = {
    Name        = "${var.environment}-mysql-memory-alarm"
    Environment = var.environment
  }
}

# VM Scale Set high CPU alert (replaces ASG EC2 CPUUtilization alarm > 70%)
resource "azurerm_monitor_metric_alert" "vmss_cpu" {
  name                = "${var.environment}-vmss-high-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.vmss_id]
  description         = "Alerts when VM Scale Set CPU utilization exceeds 70%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 70
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = {
    Name        = "${var.environment}-vmss-cpu-alarm"
    Environment = var.environment
  }
}
