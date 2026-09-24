# Deploy Java Application on Azure 3-Tier Architecture

![Azure Architecture](https://imgur.com/b9iHwVc.png)

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture Overview](#architecture-overview)
3. [Pre-Requisites](#pre-requisites)
4. [Infrastructure Setup](#infrastructure-setup)
   - [Virtual Network and Networking](#virtual-network-and-networking)
   - [Security Configuration](#security-configuration)
   - [Database Layer](#database-layer)
5. [Application Setup](#application-setup)
   - [Build Environment](#build-environment)
   - [Application Deployment](#application-deployment)
   - [Load Balancing and Auto Scaling](#load-balancing-and-auto-scaling)
6. [Monitoring and Maintenance](#monitoring-and-maintenance)
7. [Security Best Practices](#security-best-practices)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Contributing](#contributing)

---

![3-tier Architecture Diagram](https://imgur.com/3XF0tlJ.png)

---

# Project Overview

## Introduction

This project demonstrates the deployment of a production-grade Java web application using Microsoft Azure's robust 3-tier architecture. The implementation follows cloud-native best practices, ensuring high availability, scalability, and security across all application tiers.

> The Terraform code for this Azure deployment lives in [`infrastructure-azure/`](./infrastructure-azure). An earlier AWS version is preserved in [`infrastructure/`](./infrastructure) for reference.

### Key Features

- **High Availability**: Zone-redundant deployment with automated failover
- **Auto Scaling**: Dynamic resource allocation based on demand
- **Security**: Defense-in-depth approach with multiple security layers
- **Monitoring**: Comprehensive logging and monitoring setup
- **Cost Optimization**: Efficient resource utilization and management

## Architecture Overview

### Infrastructure Components

1. **Presentation Tier (Frontend)**
   - Nginx web servers in a Virtual Machine Scale Set
   - Public-facing Application Gateway (Layer 7 load balancer)
   - Azure CDN for static content

2. **Application Tier (Backend)**
   - Apache Tomcat servers in a Virtual Machine Scale Set
   - Internal load balancing via Application Gateway backend pools
   - Session management with Azure Cache for Redis

3. **Data Tier**
   - Azure Database for MySQL Flexible Server with zone-redundant HA
   - Automated backups and point-in-time restore
   - Read replicas for read-heavy workloads

### Network Architecture

- **Virtual Network (VNet) Design**
  - VNet with address space `192.168.0.0/16`
  - Public and private subnets across multiple availability zones
  - A delegated subnet for MySQL Flexible Server VNet integration
  - VNet peering for inter-VNet communication when required

# Pre-Requisites

## Required Accounts and Tools

### 1. Azure Account Setup
- Create an [Azure Free Account](https://azure.microsoft.com/free/)
- Install the Azure CLI
  ```bash
  # For Linux
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

  # For macOS
  brew install azure-cli

  # Sign in
  az login
  az account set --subscription "<your-subscription-id>"
  ```

### 2. Development Tools
- **Git**: Version control system
  ```bash
  # For Linux
  sudo apt-get update
  sudo apt-get install git

  # For macOS
  brew install git
  ```

- **Terraform**: Infrastructure as Code
  ```bash
  # For Linux
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
  wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install terraform

  # For macOS
  brew tap hashicorp/tap
  brew install hashicorp/tap/terraform
  ```

### 3. CI/CD Integration
- **SonarCloud Account**
  - Sign up at [SonarCloud](https://sonarcloud.io/)
  - Generate authentication token
  - Configure project settings:
    ```bash
    # Add to pom.xml
    <properties>
        <sonar.projectKey>your_project_key</sonar.projectKey>
        <sonar.organization>your_organization</sonar.organization>
        <sonar.host.url>https://sonarcloud.io</sonar.host.url>
    </properties>
    ```

- **JFrog Artifactory**
  - Create account on [JFrog Cloud](https://jfrog.com/start-free/)
  - Set up Maven repository
  - Configure authentication:
    ```xml
    <!-- settings.xml -->
    <servers>
        <server>
            <id>jfrog-artifactory</id>
            <username>${env.JFROG_USERNAME}</username>
            <password>${env.JFROG_PASSWORD}</password>
        </server>
    </servers>
    ```

# Infrastructure Setup

This project provisions the same Azure infrastructure in **two equivalent ways**:

- **Terraform (recommended)** — declarative Infrastructure as Code in
  [`infrastructure-azure/`](./infrastructure-azure). This is the source of truth:
  it manages state and lets you `apply`/`destroy` everything at once.
- **Azure CLI** — the imperative, step-by-step equivalent, useful for learning
  what each resource is.

Both paths create **the same resources with the same names and values**. The
examples below assume `environment = "dev"` and `location = "southeastasia"`, which
yields resource names such as `dev-java-app-rg`, `dev-vnet`, `dev-mysql-server`.
Adjust the `dev-` prefix and region if you change those inputs.

> Reference of shared values: resource group `dev-java-app-rg`, VNet
> `dev-vnet` (`192.168.0.0/16`), public subnet `dev-public-subnet-1`
> (`192.168.1.0/24`), private subnet `dev-private-subnet-1` (`192.168.3.0/24`),
> database subnet `dev-database-subnet` (`192.168.10.0/24`).

### Option A — Terraform (all tiers at once)

```bash
cd infrastructure-azure
terraform init

# Provide required variables via terraform.tfvars
cat > terraform.tfvars <<'EOF'
environment          = "dev"
location             = "southeastasia"
vnet_cidr            = "192.168.0.0/16"
public_subnets       = ["192.168.1.0/24", "192.168.2.0/24"]
private_subnets      = ["192.168.3.0/24", "192.168.4.0/24"]
db_username          = "mysqladmin"
db_password          = "YourSecurePassword"
admin_ssh_public_key = "ssh-rsa AAAA... your-key"
allowed_ssh_source_ranges = ["<your-ip>/32"]
EOF

terraform plan -out=tfplan
terraform apply tfplan
```

This single apply creates the VNet, subnets, NAT gateway, NSGs, MySQL Flexible
Server, Application Gateway, VM Scale Set and monitoring. The sections below map
each tier to its Terraform module and the equivalent Azure CLI commands.

## Virtual Network and Networking

Terraform module: [`modules/network`](./infrastructure-azure/modules/network).

### 1. Resource Group and VNet Creation

**Terraform** (root `main.tf` + network module):
```hcl
resource "azurerm_resource_group" "main" {
  name     = "${var.environment}-java-app-rg" # dev-java-app-rg
  location = var.location                     # southeastasia
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.environment}-vnet" # dev-vnet
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  address_space       = [var.vnet_cidr]           # 192.168.0.0/16
}
```

**Azure CLI** (equivalent):
```bash
az group create \
    --name dev-java-app-rg \
    --location southeastasia

az network vnet create \
    --resource-group dev-java-app-rg \
    --name dev-vnet \
    --address-prefix 192.168.0.0/16 \
    --location southeastasia
```

### 2. Subnet Configuration

**Terraform**:
```hcl
resource "azurerm_subnet" "public" {
  name                 = "${var.environment}-public-subnet-1" # dev-public-subnet-1
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnets[0]]              # 192.168.1.0/24
}

resource "azurerm_subnet" "private" {
  name                 = "${var.environment}-private-subnet-1" # dev-private-subnet-1
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_subnets[0]]              # 192.168.3.0/24
}
```

**Azure CLI**:
```bash
# Public (gateway) subnet
az network vnet subnet create \
    --resource-group dev-java-app-rg \
    --vnet-name dev-vnet \
    --name dev-public-subnet-1 \
    --address-prefixes 192.168.1.0/24

# Private (application) subnet
az network vnet subnet create \
    --resource-group dev-java-app-rg \
    --vnet-name dev-vnet \
    --name dev-private-subnet-1 \
    --address-prefixes 192.168.3.0/24
```

### 3. Outbound Connectivity (NAT Gateway)

**Terraform**:
```hcl
resource "azurerm_public_ip" "nat" {
  name                = "${var.environment}-nat-pip" # dev-nat-pip
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "main" {
  name                = "${var.environment}-nat" # dev-nat
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Standard"
}
```

**Azure CLI**:
```bash
az network public-ip create \
    --resource-group dev-java-app-rg \
    --name dev-nat-pip \
    --sku Standard \
    --allocation-method Static

az network nat gateway create \
    --resource-group dev-java-app-rg \
    --name dev-nat \
    --public-ip-addresses dev-nat-pip

# Associate the NAT gateway with the private subnet
az network vnet subnet update \
    --resource-group dev-java-app-rg \
    --vnet-name dev-vnet \
    --name dev-private-subnet-1 \
    --nat-gateway dev-nat
```

## Security Configuration

Terraform module: [`modules/security`](./infrastructure-azure/modules/security).
It creates four NSGs: `dev-gateway-nsg`, `dev-app-nsg`, `dev-db-nsg`,
`dev-bastion-nsg`.

### 1. Network Security Groups

**Terraform** (gateway NSG shown; app/db/bastion follow the same pattern):
```hcl
resource "azurerm_network_security_group" "gateway" {
  name                = "${var.environment}-gateway-nsg" # dev-gateway-nsg
  resource_group_name = var.resource_group_name
  location            = var.location

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
    # ...same shape, destination_port_range = "443"
  }
}
```

**Azure CLI**:
```bash
az network nsg create \
    --resource-group dev-java-app-rg \
    --name dev-gateway-nsg

az network nsg rule create \
    --resource-group dev-java-app-rg \
    --nsg-name dev-gateway-nsg \
    --name AllowHTTP \
    --priority 100 \
    --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes Internet \
    --destination-port-ranges 80

az network nsg rule create \
    --resource-group dev-java-app-rg \
    --nsg-name dev-gateway-nsg \
    --name AllowHTTPS \
    --priority 110 \
    --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes Internet \
    --destination-port-ranges 443
```

The database NSG (`dev-db-nsg`) allows MySQL (3306) only from the VNet, and the
bastion NSG (`dev-bastion-nsg`) allows SSH (22) only from
`allowed_ssh_source_ranges`.

## Database Layer

Terraform module: [`modules/database`](./infrastructure-azure/modules/database).

### 1. MySQL Flexible Server Creation

**Terraform**:
```hcl
resource "azurerm_mysql_flexible_server" "main" {
  name                = "${var.environment}-mysql-server" # dev-mysql-server
  resource_group_name = var.resource_group_name
  location            = var.location

  administrator_login    = var.db_username # mysqladmin
  administrator_password = var.db_password

  version  = "8.0.21"
  sku_name = "B_Standard_B1ms"

  delegated_subnet_id = var.delegated_subnet_id # dev-database-subnet
  private_dns_zone_id = var.private_dns_zone_id

  storage {
    size_gb = 20
  }

  high_availability {
    mode = "ZoneRedundant"
  }
}

resource "azurerm_mysql_flexible_database" "main" {
  name        = var.db_name # javaapp
  server_name = azurerm_mysql_flexible_server.main.name
  # ...
}
```

**Azure CLI** (equivalent):
```bash
az mysql flexible-server create \
    --resource-group dev-java-app-rg \
    --name dev-mysql-server \
    --location southeastasia \
    --admin-user mysqladmin \
    --admin-password "YourSecurePassword" \
    --sku-name Standard_B1ms \
    --tier Burstable \
    --version 8.0.21 \
    --storage-size 20 \
    --high-availability ZoneRedundant \
    --vnet dev-vnet \
    --subnet dev-database-subnet

# Create the application database
az mysql flexible-server db create \
    --resource-group dev-java-app-rg \
    --server-name dev-mysql-server \
    --database-name javaapp
```

### 2. Database Initialization
```sql
-- Connect to database (TLS enforced)
mysql -h your-server.mysql.database.azure.com -u mysqladmin -p

-- Create application database
CREATE DATABASE javaapp;
USE javaapp;

-- Create users table
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create necessary indexes
CREATE INDEX idx_username ON users(username);
CREATE INDEX idx_email ON users(email);
```

# Application Setup

## Build Environment

### 1. Maven Configuration
```xml
<!-- pom.xml -->
<project>
    <properties>
        <java.version>11</java.version>
        <spring.version>2.5.12</spring.version>
    </properties>
    
    <dependencies>
        <!-- Add your dependencies here -->
    </dependencies>
    
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
```

### 2. Build Process
```bash
# Clean and build project
mvn clean package -DskipTests

# Run tests
mvn test

# Deploy to JFrog
mvn deploy
```

## Application Deployment

### 1. Tomcat Configuration
```bash
# Create tomcat.service
sudo tee /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
Environment=CATALINA_HOME=/opt/tomcat
Environment=CATALINA_BASE=/opt/tomcat
Environment='CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC'
Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom'

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

User=tomcat
Group=tomcat
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
```

### 2. Nginx Configuration
```nginx
# /etc/nginx/conf.d/app.conf
upstream backend {
    server <application-gateway-private-ip>:8080;
}

server {
    listen 80;
    server_name example.com;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /static/ {
        proxy_pass https://your-azure-cdn-endpoint.azureedge.net;
    }
}
```

## Load Balancing and Auto Scaling

Terraform modules: [`modules/appgw`](./infrastructure-azure/modules/appgw)
(Application Gateway `dev-appgw`, listener on port 80 → backend 8080) and
[`modules/vmss`](./infrastructure-azure/modules/vmss) (VM Scale Set `dev-vmss`).

### 1. VM Scale Set Creation

**Terraform**:
```hcl
resource "azurerm_linux_virtual_machine_scale_set" "main" {
  name                = "${var.environment}-vmss" # dev-vmss
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vm_size   # Standard_B1ms
  instances           = var.instances # 2

  admin_username                  = var.admin_username # azureuser
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  custom_data = base64encode(file("cloud-init.txt")) # installs Java 11 + Tomcat

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2" # Ubuntu 22.04
    version   = "latest"
  }

  network_interface {
    name    = "${var.environment}-vmss-nic"
    primary = true
    ip_configuration {
      name                                         = "internal"
      primary                                      = true
      subnet_id                                    = var.private_subnet_id # dev-private-subnet-1
      application_gateway_backend_address_pool_ids = var.backend_address_pool_ids
    }
  }
}
```

**Azure CLI** (equivalent):
```bash
az vmss create \
    --resource-group dev-java-app-rg \
    --name dev-vmss \
    --image Ubuntu2204 \
    --vm-sku Standard_B1ms \
    --instance-count 2 \
    --vnet-name dev-vnet \
    --subnet dev-private-subnet-1 \
    --admin-username azureuser \
    --ssh-key-values ~/.ssh/id_rsa.pub \
    --custom-data cloud-init.txt \
    --app-gateway dev-appgw \
    --backend-pool-name dev-appgw-beap
```

### 2. Autoscale Configuration

**Terraform**:
```hcl
resource "azurerm_monitor_autoscale_setting" "main" {
  name                = "${var.environment}-vmss-autoscale" # dev-vmss-autoscale
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.main.id

  profile {
    name = "default"
    capacity {
      default = var.instances     # 2
      minimum = var.min_instances # 2
      maximum = var.max_instances # 6
    }

    rule { # scale out when CPU > 70%
      metric_trigger {
        metric_name = "Percentage CPU"
        operator    = "GreaterThan"
        threshold   = 70
        # ...
      }
      scale_action {
        direction = "Increase"
        value     = "1"
      }
    }

    rule { # scale in when CPU < 30%
      metric_trigger {
        metric_name = "Percentage CPU"
        operator    = "LessThan"
        threshold   = 30
        # ...
      }
      scale_action {
        direction = "Decrease"
        value     = "1"
      }
    }
  }
}
```

**Azure CLI** (equivalent):
```bash
az monitor autoscale create \
    --resource-group dev-java-app-rg \
    --resource dev-vmss \
    --resource-type Microsoft.Compute/virtualMachineScaleSets \
    --name dev-vmss-autoscale \
    --min-count 2 --max-count 6 --count 2

# Scale out when average CPU exceeds 70%
az monitor autoscale rule create \
    --resource-group dev-java-app-rg \
    --autoscale-name dev-vmss-autoscale \
    --condition "Percentage CPU > 70 avg 5m" \
    --scale out 1

# Scale in when average CPU drops below 30%
az monitor autoscale rule create \
    --resource-group dev-java-app-rg \
    --autoscale-name dev-vmss-autoscale \
    --condition "Percentage CPU < 30 avg 5m" \
    --scale in 1
```

# Monitoring and Maintenance

Terraform module: [`modules/monitoring`](./infrastructure-azure/modules/monitoring).
It creates a Log Analytics workspace (`dev-application-law`), an action group
(`dev-alerts-ag`), and metric alerts for MySQL CPU (>80%), MySQL memory (>90%)
and VMSS CPU (>70%).

## Azure Monitor Setup

### 1. Metrics and Alerts Configuration

**Terraform**:
```hcl
resource "azurerm_monitor_action_group" "main" {
  name                = "${var.environment}-alerts-ag" # dev-alerts-ag
  resource_group_name = var.resource_group_name
  short_name          = "alerts"
}

resource "azurerm_monitor_metric_alert" "vmss_cpu" {
  name                = "${var.environment}-vmss-high-cpu" # dev-vmss-high-cpu
  resource_group_name = var.resource_group_name
  scopes              = [var.vmss_id]
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
}
```

**Azure CLI** (equivalent):
```bash
az monitor action-group create \
    --resource-group dev-java-app-rg \
    --name dev-alerts-ag \
    --short-name alerts

# Alert when VMSS CPU exceeds 70%
az monitor metrics alert create \
    --resource-group dev-java-app-rg \
    --name dev-vmss-high-cpu \
    --scopes "/subscriptions/<sub-id>/resourceGroups/dev-java-app-rg/providers/Microsoft.Compute/virtualMachineScaleSets/dev-vmss" \
    --condition "avg Percentage CPU > 70" \
    --window-size 5m \
    --evaluation-frequency 5m \
    --action dev-alerts-ag
```

### 2. Log Management

**Terraform**:
```hcl
resource "azurerm_log_analytics_workspace" "application" {
  name                = "${var.environment}-application-law" # dev-application-law
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
```

**Azure CLI** (equivalent):
```bash
az monitor log-analytics workspace create \
    --resource-group dev-java-app-rg \
    --workspace-name dev-application-law \
    --retention-time 30

# Enable the Azure Monitor Agent on the scale set to collect Tomcat logs
# (catalina.out) and system metrics such as memory and swap usage.
az vmss extension set \
    --resource-group dev-java-app-rg \
    --vmss-name dev-vmss \
    --name AzureMonitorLinuxAgent \
    --publisher Microsoft.Azure.Monitor
```

# Security Best Practices

## 1. Network Security
- Apply Network Security Groups per tier
- Use Application Security Groups for grouping workloads
- Enable NSG Flow Logs to a Log Analytics workspace
- Configure Azure Web Application Firewall (WAF) on Application Gateway

## 2. Application Security
- Regular security patches
- Enable Azure DDoS Protection
- Use Azure Key Vault for secrets
- Enable Microsoft Defender for Cloud

## 3. Data Security
- Enable encryption at rest (enabled by default on Azure managed disks and MySQL)
- Enforce SSL/TLS for data in transit (`require_secure_transport = ON`)
- Regular security audits
- Implement backup strategies

# Troubleshooting Guide

## Common Issues and Solutions

### 1. Connection Issues
```bash
# Check connectivity to the database
nc -zv dev-mysql-server.mysql.database.azure.com 3306

# Verify NSG rules
az network nsg rule list --resource-group dev-java-app-rg --nsg-name dev-db-nsg -o table

# Check Application Gateway backend health
az network application-gateway show-backend-health \
    --resource-group dev-java-app-rg \
    --name dev-appgw
```

### 2. Performance Issues
```bash
# Check CPU usage
top -bn1

# Monitor memory usage
free -m

# Check disk usage
df -h

# Monitor Tomcat threads
ps -eLf | grep java | wc -l
```

# Contributing

## How to Contribute

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Development Setup

```bash
# Clone repository
git clone https://github.com/yourusername/your-repo.git

# Install dependencies
mvn install

# Run tests
mvn test
```

---

## 🛠️ Author & Community

This project is maintained by **[Harshhaa](https://github.com/NotHarshhaa)** 💡.
Your feedback and contributions are welcome!

📧 **Connect with me:**
- **GitHub**: [@NotHarshhaa](https://github.com/NotHarshhaa)
- **Blog**: [ProDevOpsGuy](https://blog.prodevopsguytech.com)
- **Telegram Community**: [Join Here](https://t.me/prodevopsguy)
- **LinkedIn**: [Harshhaa Vardhan Reddy](https://www.linkedin.com/in/harshhaa-vardhan-reddy/)

---

## ⭐ Support the Project

If you found this project helpful, please consider:
- **Starring** ⭐ the repository
- **Sharing** it with your network
- **Contributing** to its improvement

### 📢 Stay Connected

![Follow Me](https://imgur.com/2j7GSPs.png)

> [!Important]
> This documentation is continuously evolving. For the latest updates, please check the repository regularly.
