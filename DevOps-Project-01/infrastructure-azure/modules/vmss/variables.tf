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

variable "private_subnet_id" {
  description = "ID of the private subnet for scale set instances"
  type        = string
}

variable "network_security_group_id" {
  description = "ID of the application NSG to associate with instances"
  type        = string
}

variable "backend_address_pool_ids" {
  description = "List of Application Gateway backend address pool IDs"
  type        = list(string)
}

variable "vm_size" {
  description = "Azure VM size for scale set instances"
  type        = string
}

variable "admin_username" {
  description = "Administrator username for VM instances"
  type        = string
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VM administrator access"
  type        = string
}

variable "instances" {
  description = "Initial number of instances in the scale set"
  type        = number
}

variable "min_instances" {
  description = "Minimum number of instances (autoscale)"
  type        = number
}

variable "max_instances" {
  description = "Maximum number of instances (autoscale)"
  type        = number
}
