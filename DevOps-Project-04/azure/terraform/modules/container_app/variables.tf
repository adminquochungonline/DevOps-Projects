variable "name_prefix" {
  description = "Name of the container app (e.g. dev-django-app)"
  type        = string
}

variable "location" {
  description = "Azure region (kept for interface symmetry; the app inherits the environment region)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group holding the container app"
  type        = string
}

variable "container_app_environment_id" {
  description = "Resource ID of the Container Apps environment"
  type        = string
}

variable "managed_identity_id" {
  description = "Resource ID of the user-assigned identity used for registry pulls"
  type        = string
}

variable "registry_login_server" {
  description = "Registry login server, e.g. devdjangodp04hung.azurecr.io"
  type        = string
}

variable "container_image" {
  description = "Fully qualified image reference including tag"
  type        = string
}

variable "revision_suffix" {
  description = "Revision suffix. Empty derives it from the image tag."
  type        = string
  default     = ""
}

variable "django_secret_key" {
  description = "Django SECRET_KEY, stored as a container app secret"
  type        = string
  sensitive   = true
}

variable "allowed_hosts" {
  description = "Comma separated Django ALLOWED_HOSTS"
  type        = string
  default     = "*"
}

variable "csrf_trusted_origins" {
  description = "Comma separated Django CSRF_TRUSTED_ORIGINS"
  type        = string
  default     = ""
}

variable "target_port" {
  description = "Container listening port"
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "vCPU per replica"
  type        = number
  default     = 0.5
}

variable "memory" {
  description = "Memory per replica (must pair with cpu)"
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum replicas (0 enables scale-to-zero)"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum replicas"
  type        = number
  default     = 10
}

variable "concurrent_requests" {
  description = "Concurrent requests per replica that trigger scale-out"
  type        = number
  default     = 50
}

variable "external_ingress" {
  description = "Publish the app publicly (true) or keep ingress internal (false)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
