variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "southeastasia"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "vnet_cidr" {
  description = "CIDR block for the Virtual Network"
  type        = string
  default     = "192.168.0.0/16"
}

variable "public_subnets" {
  description = "CIDR blocks for public (gateway) subnets"
  type        = list(string)
  default     = ["192.168.1.0/24", "192.168.2.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for private (application/database) subnets"
  type        = list(string)
  default     = ["192.168.3.0/24", "192.168.4.0/24"]
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "javaapp"
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

variable "vm_size" {
  description = "Azure VM size for scale set instances"
  type        = string
  default     = "Standard_B1ms"
}

variable "admin_username" {
  description = "Administrator username for VM instances"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VM administrator access"
  type        = string
}

variable "vmss_instances" {
  description = "Initial number of instances in the scale set"
  type        = number
  default     = 2
}

variable "vmss_min_instances" {
  description = "Minimum number of instances in the scale set"
  type        = number
  default     = 2
}

variable "vmss_max_instances" {
  description = "Maximum number of instances in the scale set"
  type        = number
  default     = 6
}

variable "allowed_ssh_source_ranges" {
  description = "List of source address ranges allowed to SSH to the bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Restrict this in production
}
