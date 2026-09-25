variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group holding the registry"
  type        = string
}

variable "registry_name" {
  description = "Registry name. Globally unique, 5-50 alphanumeric characters, lowercase."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.registry_name))
    error_message = "registry_name must be 5-50 lowercase alphanumeric characters."
  }
}

variable "sku" {
  description = "Registry SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
}

variable "untagged_retention_days" {
  description = "Days an untagged manifest is kept before ACR deletes it (Premium only)"
  type        = number
  default     = 7
}

variable "pull_principal_ids" {
  description = "Principal object IDs granted AcrPull"
  type        = list(string)
  default     = []
}

variable "push_principal_id" {
  description = "Principal object ID granted AcrPush (empty to skip)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
