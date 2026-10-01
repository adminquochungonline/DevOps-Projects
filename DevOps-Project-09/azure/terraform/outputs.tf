output "resource_group_name" {
  description = "Tên Resource Group"
  value       = azurerm_resource_group.rg.name
}

output "vm_public_ip" {
  description = "Địa chỉ Public IP của VM DevSecOps trên Azure"
  value       = azurerm_public_ip.pip.ip_address
}

output "ssh_command" {
  description = "Lệnh SSH để kết nối vào máy chủ Azure VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "jenkins_url" {
  description = "Đường dẫn truy cập Jenkins"
  value       = "http://${azurerm_public_ip.pip.ip_address}:8080"
}

output "sonarqube_url" {
  description = "Đường dẫn truy cập SonarQube"
  value       = "http://${azurerm_public_ip.pip.ip_address}:9000"
}

output "grafana_url" {
  description = "Đường dẫn truy cập Grafana"
  value       = "http://${azurerm_public_ip.pip.ip_address}:3000"
}

output "prometheus_url" {
  description = "Đường dẫn truy cập Prometheus"
  value       = "http://${azurerm_public_ip.pip.ip_address}:9090"
}

output "netflix_app_url" {
  description = "Đường dẫn truy cập ứng dụng Netflix Clone (Docker)"
  value       = "http://${azurerm_public_ip.pip.ip_address}:8081"
}

output "acr_login_server" {
  description = "Azure Container Registry Login Server"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_admin_username" {
  description = "Azure Container Registry Username"
  value       = azurerm_container_registry.acr.admin_username
  sensitive   = false
}

output "acr_admin_password" {
  description = "Azure Container Registry Password"
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}

output "aks_cluster_name" {
  description = "Tên cụm AKS (nếu bật enable_aks)"
  value       = var.enable_aks ? azurerm_kubernetes_cluster.aks[0].name : "AKS is disabled"
}
