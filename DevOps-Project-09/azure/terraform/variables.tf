variable "resource_group_name" {
  type        = string
  description = "Tên Azure Resource Group (để trống sẽ tự sinh theo environment-prefix-name_suffix-rg)"
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure Region (ví dụ: southeastasia, eastus)"
  default     = "southeastasia"
}

variable "prefix" {
  type        = string
  description = "Tiền tố đặt tên cho các tài nguyên"
  default     = "netflix"
}

variable "environment" {
  type        = string
  description = "Môi trường triển khai (dev, staging, prod)"
  default     = "dev"
}

variable "name_suffix" {
  type        = string
  description = "Hậu tố định danh duy nhất (ví dụ: hung, dp09hung)"
  default     = "dp09hung"
}

variable "vm_size" {
  type        = string
  description = "Kích thước Azure VM (chạy Docker DevSecOps stack: khuyến nghị tối thiểu 2 vCPU, 8GB RAM)"
  default     = "Standard_B2ms"
}

variable "admin_username" {
  type        = string
  description = "Tên user quản trị VM Ubuntu"
  default     = "azureuser"
}

variable "ssh_public_key" {
  type        = string
  description = "Nội dung SSH Public Key dạng chuỗi (thường truyền từ Jenkins credential vmss-ssh-pubkey)"
  default     = ""
}

variable "ssh_public_key_path" {
  type        = string
  description = "Đường dẫn file SSH public key nếu không truyền ssh_public_key trực tiếp"
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_source_ip" {
  type        = string
  description = "Địa chỉ IP nguồn được phép truy cập SSH/Jenkins/SonarQube/Monitoring (dùng * cho lab hoặc IP cá nhân/CIDR)"
  default     = "*"
}

variable "enable_aks" {
  type        = bool
  description = "Bật/Tắt triển khai cụm Azure Kubernetes Service (AKS)"
  default     = false
}

variable "aks_node_count" {
  type        = number
  description = "Số lượng node worker trong cụm AKS"
  default     = 1
}

variable "aks_vm_size" {
  type        = string
  description = "Cấu hình VM của node trong AKS"
  default     = "Standard_B2s"
}

variable "tags" {
  type        = map(string)
  description = "Tags gán cho tài nguyên Azure"
  default = {
    Project     = "DevSecOps-Netflix-Azure"
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}
