# VM Scale Set Module
# Linux Virtual Machine Scale Set (replaces AWS Auto Scaling Group + Launch
# Template). Instances run in the private subnet, join the Application Gateway
# backend pool, and are provisioned with Java 11 + Tomcat via cloud-init.
# An autoscale profile scales on CPU utilization.

locals {
  # cloud-init user data: install Java 11 and Tomcat, enable and start service.
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y openjdk-11-jdk tomcat9
    systemctl enable tomcat9
    systemctl start tomcat9
  EOF
  )
}

resource "azurerm_linux_virtual_machine_scale_set" "main" {
  name                = "${var.environment}-vmss"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.vm_size
  instances           = var.instances

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  custom_data = local.custom_data

  # Ubuntu 22.04 LTS image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name                      = "${var.environment}-vmss-nic"
    primary                   = true
    network_security_group_id = var.network_security_group_id

    ip_configuration {
      name                                         = "internal"
      primary                                      = true
      subnet_id                                    = var.private_subnet_id
      application_gateway_backend_address_pool_ids = var.backend_address_pool_ids
    }
  }

  # Roll instances gradually when the model changes (zero-downtime style)
  upgrade_mode = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 20
    pause_time_between_batches              = "PT30S"
  }

  # Health probe via Application Gateway backend pool requires an extension or
  # automatic OS upgrade health; keep automatic instance repair off by default.
  tags = {
    Name        = "${var.environment}-web-instance"
    Environment = var.environment
  }
}

# Autoscale settings (equivalent to ASG min/max/desired + CPU policy)
resource "azurerm_monitor_autoscale_setting" "main" {
  name                = "${var.environment}-vmss-autoscale"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.main.id

  profile {
    name = "default"

    capacity {
      default = var.instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    # Scale out when average CPU exceeds 70%
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in when average CPU drops below 30%
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = {
    Environment = var.environment
  }
}
