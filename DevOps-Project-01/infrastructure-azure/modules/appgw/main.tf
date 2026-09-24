# Application Gateway Module
# Azure Application Gateway v2 (replaces AWS Application Load Balancer).
# Public-facing L7 load balancer that listens on port 80 and forwards to the
# backend application pool on port 8080, with an HTTP health probe.

locals {
  backend_address_pool_name      = "${var.environment}-appgw-beap"
  frontend_port_name             = "${var.environment}-appgw-feport"
  frontend_ip_configuration_name = "${var.environment}-appgw-feip"
  http_setting_name              = "${var.environment}-appgw-be-http"
  listener_name                  = "${var.environment}-appgw-httplstn"
  request_routing_rule_name      = "${var.environment}-appgw-rqrt"
  probe_name                     = "${var.environment}-appgw-probe"
}

# Static public IP for the Application Gateway frontend
resource "azurerm_public_ip" "appgw" {
  name                = "${var.environment}-appgw-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Name        = "${var.environment}-appgw-pip"
    Environment = var.environment
  }
}

resource "azurerm_application_gateway" "main" {
  name                = "${var.environment}-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  # Azure rejects the implicit legacy default (AppGwSslPolicy20150501, TLS 1.0/1.1).
  # Use a modern predefined policy that enforces TLS 1.2+.
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "${var.environment}-appgw-ipcfg"
    subnet_id = var.public_subnet_id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Backend pool is populated dynamically by the VM Scale Set
  backend_address_pool {
    name = local.backend_address_pool_name
  }

  # Health probe equivalent to the ALB target group health check ("/" on 8080)
  probe {
    name                                      = local.probe_name
    protocol                                  = "Http"
    path                                      = "/"
    host                                      = "127.0.0.1"
    pick_host_name_from_backend_http_settings = false
    interval                                  = 30
    timeout                                   = 5
    unhealthy_threshold                       = 2

    match {
      status_code = ["200"]
    }
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = local.probe_name
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
    priority                   = 100
  }

  tags = {
    Name        = "${var.environment}-appgw"
    Environment = var.environment
  }

  # The VMSS manages backend pool membership; ignore drift on those fields
  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      request_routing_rule,
      tags,
    ]
  }
}
