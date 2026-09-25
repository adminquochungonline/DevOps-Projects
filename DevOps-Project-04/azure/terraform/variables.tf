variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "southeastasia"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod). Used as the resource name prefix."
  type        = string
  default     = "dev"
}

variable "name_suffix" {
  description = "Globally-unique suffix for the container registry name, so the pipelines can derive the registry name by convention instead of reading Terraform state."
  type        = string
  default     = "dp04hung"
}

# --- Container registry -------------------------------------------------------

variable "acr_sku" {
  description = "Container Registry SKU. Premium is required for private endpoints, geo-replication and content trust."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be one of Basic, Standard or Premium."
  }
}

variable "acr_untagged_retention_days" {
  description = "Days an untagged manifest is kept before ACR deletes it (the closest equivalent to an ECR lifecycle policy). Requires the Premium SKU; ignored on Basic/Standard."
  type        = number
  default     = 7
}

variable "cicd_principal_id" {
  description = "Object ID of the Jenkins service principal, granted AcrPush so the app pipeline can run 'az acr build'. Leave empty if the SP is already Contributor on the subscription."
  type        = string
  default     = ""
}

# --- Application image --------------------------------------------------------

variable "container_image" {
  description = "Fully qualified image reference, e.g. devdjangodp04hung.azurecr.io/django-app:42. Empty means 'provision the platform only' and skips the container app (first apply, before any image exists)."
  type        = string
  default     = ""
}

variable "django_secret_key" {
  description = "Django SECRET_KEY, injected as a Container Apps secret. Required whenever container_image is set."
  type        = string
  default     = ""
  sensitive   = true
}

variable "allowed_hosts" {
  description = "Comma separated Django ALLOWED_HOSTS. Narrow this to the ingress FQDN once it is known."
  type        = string
  default     = "*"
}

variable "csrf_trusted_origins" {
  description = "Comma separated Django CSRF_TRUSTED_ORIGINS, e.g. https://app.contoso.com. Needed for form POSTs behind a custom domain."
  type        = string
  default     = ""
}

# --- Runtime sizing and scaling ----------------------------------------------

variable "target_port" {
  description = "Port the container listens on (gunicorn bind port)"
  type        = number
  default     = 8000
}

variable "container_cpu" {
  description = "vCPU per replica. Consumption profile: 0.25 - 4 in 0.25 steps, paired with 0.5 GiB memory per 0.25 vCPU."
  type        = number
  default     = 0.5
}

variable "container_memory" {
  description = "Memory per replica, must pair with container_cpu (0.5 vCPU -> 1Gi)."
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum replicas. 0 enables scale-to-zero (cheapest, cold starts); 1 keeps a warm replica; 2+ survives losing one replica."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum replicas the HTTP autoscaler may create"
  type        = number
  default     = 10
}

variable "concurrent_requests" {
  description = "Concurrent requests per replica that trigger scale-out"
  type        = number
  default     = 50
}

variable "external_ingress" {
  description = "Publish the app on a public FQDN. false keeps ingress internal to the Container Apps environment. WARNING: public ingress has no authentication in front of it; add Entra ID auth or Front Door + WAF for real workloads."
  type        = bool
  default     = true
}

# --- Observability ------------------------------------------------------------

variable "log_retention_in_days" {
  description = "Log Analytics retention in days (30 - 730)"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for Azure Monitor alerts. Empty disables the action group and alert rules."
  type        = string
  default     = ""
}
