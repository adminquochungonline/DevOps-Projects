# Azure Infrastructure for Java Application

This directory contains Terraform configurations to deploy the Java application
on **Microsoft Azure** using a secure, scalable, highly available 3-tier
architecture. It is the Azure port of the original AWS setup in
[`../infrastructure`](../infrastructure).

## Architecture Overview

The infrastructure consists of:

- **Virtual Network (VNet)** with public and private subnets, plus a delegated
  subnet for the managed database
- **Application Gateway (v2)** in the public subnet (public entry point / L7 LB)
- **Linux VM Scale Set** in the private subnet, fronted by the Application Gateway
- **Azure Database for MySQL Flexible Server** with VNet integration and
  zone-redundant high availability
- **NAT Gateway** for outbound access from private subnets
- **Network Security Groups** for each tier
- **Azure Monitor + Log Analytics** for metrics, alerting and logging

## AWS → Azure Service Mapping

| AWS (original)                     | Azure (this port)                              |
| ---------------------------------- | ---------------------------------------------- |
| VPC + subnets + IGW                | Virtual Network + subnets                      |
| NAT Gateway + Elastic IP           | NAT Gateway + Public IP                        |
| VPC Flow Logs → CloudWatch         | NSG Flow Logs → Log Analytics workspace        |
| Security Groups                    | Network Security Groups (NSG)                  |
| RDS MySQL (Multi-AZ)               | Azure Database for MySQL Flexible Server (ZR HA) |
| Application Load Balancer (ALB)    | Application Gateway (Standard_v2)              |
| Auto Scaling Group + Launch Template | VM Scale Set + Autoscale Setting             |
| CloudWatch Alarms / Log Groups     | Azure Monitor Metric Alerts / Log Analytics    |
| IAM roles                          | Managed identities (add as needed)             |

## Prerequisites

1. **Azure Account and Credentials**
   - Azure subscription with appropriate permissions
   - Azure CLI installed and authenticated (`az login`)

2. **Tools**
   - Terraform >= 1.0.0
   - Azure CLI >= 2.0.0

## Directory Structure

```
infrastructure-azure/
├── main.tf              # Root configuration and module wiring
├── variables.tf         # Input variables
├── outputs.tf           # Root outputs
├── README.md            # This file
└── modules/
    ├── network/         # VNet, subnets, NAT gateway, private DNS, flow logs
    ├── security/        # Network Security Groups (gateway/app/db/bastion)
    ├── database/        # MySQL Flexible Server
    ├── appgw/           # Application Gateway (replaces ALB)
    ├── vmss/            # VM Scale Set + autoscale (replaces ASG)
    └── monitoring/      # Log Analytics + metric alerts
```

## Usage

1. **Authenticate with Azure**
   ```bash
   az login
   az account set --subscription "<your-subscription-id>"
   ```

2. **Initialize Terraform**
   ```bash
   terraform init
   ```

3. **Configure Variables**
   Create a `terraform.tfvars` file:
   ```hcl
   environment          = "dev"
   location             = "southeastasia"
   vnet_cidr            = "192.168.0.0/16"
   public_subnets       = ["192.168.1.0/24", "192.168.2.0/24"]
   private_subnets      = ["192.168.3.0/24", "192.168.4.0/24"]
   db_username          = "mysqladmin"
   db_password          = "your-secure-password"
   admin_ssh_public_key = "ssh-rsa AAAA... your-key"
   allowed_ssh_source_ranges = ["<your-ip>/32"]
   ```

4. **Plan the Infrastructure**
   ```bash
   terraform plan -out=tfplan
   ```

5. **Apply the Infrastructure**
   ```bash
   terraform apply tfplan
   ```

## Remote State (optional)

The `backend "azurerm"` block in `main.tf` is commented out. To store state in
an Azure Storage Account, create the storage account/container first, then fill
in and uncomment the backend block and run `terraform init`.

## Root Outputs

| Output                          | Description                                   |
| ------------------------------- | --------------------------------------------- |
| `resource_group_name`           | Name of the resource group                    |
| `vnet_id`                       | ID of the Virtual Network                     |
| `application_gateway_public_ip` | Public IP of the Application Gateway          |
| `mysql_server_fqdn`             | FQDN of the MySQL Flexible Server             |
| `vmss_id`                       | ID of the VM Scale Set                        |

## Security Considerations

- Application VMs run in private subnets; only the Application Gateway is public.
- The MySQL server uses VNet integration (private access) and enforces TLS
  (`require_secure_transport = ON`).
- `allowed_ssh_source_ranges` defaults to `0.0.0.0/0` — **restrict this in
  production** to your bastion / admin IPs.
- Consider adding a managed identity for the VM Scale Set to access Azure
  services (Key Vault, Storage) without embedded credentials.

## Notes / Follow-ups

- The Application Gateway backend pool is populated by the VM Scale Set. The
  `appgw` module ignores drift on pool membership fields to avoid conflicts.
- A bastion NSG is provided; a dedicated bastion VM (or Azure Bastion) can be
  added if SSH access to private instances is required.
- Autoscale thresholds: scale out at >70% CPU, scale in at <30% CPU.
