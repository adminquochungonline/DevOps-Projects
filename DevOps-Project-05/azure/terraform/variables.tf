variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "southeastasia"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod). Used as the resource name prefix."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.environment))
    error_message = "environment must be 1-10 lowercase letters/digits (it is part of the ACR name)."
  }
}

variable "name_suffix" {
  description = "Globally-unique suffix; the registry is named \"<environment>regapp<name_suffix>\" so the app pipeline can derive it by convention."
  type        = string
  default     = "dp05hung"

  validation {
    condition     = can(regex("^[a-z0-9]{1,30}$", var.name_suffix))
    error_message = "name_suffix must be 1-30 lowercase letters/digits (ACR names are alphanumeric only)."
  }
}

# --- Container registry -------------------------------------------------------

variable "acr_sku" {
  description = "Container Registry SKU."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be one of Basic, Standard or Premium."
  }
}

variable "manage_acr_pull_assignment" {
  description = <<-EOT
    Let Terraform grant AcrPull on the registry to the AKS kubelet identity.
    Requires the deploying principal to hold 'Microsoft.Authorization/roleAssignments/write'
    (Owner, User Access Administrator, or Role Based Access Control Administrator,
    which may be constrained to AcrPull). A Contributor-only SP gets 403.
    false = grant it by hand with the acr_pull_grant_command output.
  EOT
  type        = bool
  default     = true
}

# --- AKS ----------------------------------------------------------------------

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Empty = the region default."
  type        = string
  default     = ""
}

variable "aks_sku_tier" {
  description = "AKS control plane tier. Free has no uptime SLA; Standard adds one (paid)."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard"], var.aks_sku_tier)
    error_message = "aks_sku_tier must be Free or Standard."
  }
}

variable "node_vm_size" {
  description = "VM size of the system node pool. AKS needs at least 2 vCPU / 4 GiB. Try Standard_D2as_v5 if B-series is restricted in the region."
  type        = string
  default     = "Standard_B2s"
}

variable "node_count" {
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 5
    error_message = "node_count must be between 1 and 5."
  }
}

variable "node_os_disk_size_gb" {
  description = "OS disk size of each node (GB)."
  type        = number
  default     = 30
}
