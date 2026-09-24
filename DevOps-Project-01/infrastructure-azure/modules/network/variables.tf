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

variable "vnet_cidr" {
  description = "CIDR block for the Virtual Network"
  type        = string
}

variable "public_subnets" {
  description = "List of public (gateway) subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private (application) subnet CIDR blocks"
  type        = list(string)
}
