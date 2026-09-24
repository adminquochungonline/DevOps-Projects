variable "environment" {
  description = "Environment name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "delegated_subnet_id" {
  description = "ID of the delegated subnet for MySQL VNet integration"
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the private DNS zone for MySQL"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database administrator username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}

variable "mysql_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0.21"
}

variable "sku_name" {
  description = "MySQL Flexible Server SKU. Burstable (B_*) does not support HA; use GP_* / MO_* for high_availability_enabled = true."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "high_availability_enabled" {
  description = "Enable zone-redundant HA. Requires a General Purpose or Business Critical SKU (not Burstable)."
  type        = bool
  default     = false
}
