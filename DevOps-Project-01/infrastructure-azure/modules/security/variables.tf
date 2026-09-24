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

variable "allowed_ssh_source_ranges" {
  description = "List of source address ranges allowed to SSH to the bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Restrict this in production
}
