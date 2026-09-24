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

variable "mysql_server_id" {
  description = "ID of the MySQL Flexible Server to monitor"
  type        = string
}

variable "vmss_id" {
  description = "ID of the VM Scale Set to monitor"
  type        = string
}
