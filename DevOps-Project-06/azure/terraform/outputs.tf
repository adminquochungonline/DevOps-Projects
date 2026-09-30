output "resource_group_name" {
  description = "Resource group holding the registry and the cluster"
  value       = azurerm_resource_group.main.name
}

output "acr_name" {
  description = "Container registry name"
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Registry login server, prefix of every image reference"
  value       = azurerm_container_registry.main.login_server
}

output "aks_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_node_resource_group" {
  description = "Resource group AKS manages (nodes, load balancer, public IPs)"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity that pulls images from ACR"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "get_credentials_command" {
  description = "Fetch a kubeconfig for the cluster"
  value       = "az aks get-credentials -g ${azurerm_resource_group.main.name} -n ${azurerm_kubernetes_cluster.main.name}"
}

output "acr_pull_grant_command" {
  description = "Manual AcrPull grant, only needed when manage_acr_pull_assignment = false (run with Owner / User Access Administrator)"
  value       = "az role assignment create --assignee-object-id ${azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id} --assignee-principal-type ServicePrincipal --role AcrPull --scope ${azurerm_container_registry.main.id}"
}
