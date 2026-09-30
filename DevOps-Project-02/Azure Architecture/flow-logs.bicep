targetScope = 'resourceGroup'

@description('Name of the resource group containing the existing regional Network Watcher.')
param networkWatcherResourceGroupName string = 'NetworkWatcherRG'

@description('Name of the existing Network Watcher, for example NetworkWatcher_southeastasia.')
param networkWatcherName string

@description('Resource IDs of the management and application VNets.')
param virtualNetworkResourceIds array

@description('Resource ID of the storage account used for flow-log retention.')
param storageAccountResourceId string

@description('Resource ID of the Log Analytics workspace used by Traffic Analytics.')
param logAnalyticsWorkspaceResourceId string

@description('Log Analytics workspace GUID (customerId), not its ARM resource ID.')
param logAnalyticsWorkspaceId string

@description('Region of the Network Watcher and Log Analytics workspace.')
param logAnalyticsWorkspaceRegion string = resourceGroup().location

@minValue(0)
@maxValue(365)
param retentionDays int = 30

module vnetFlowLogs 'flow-logs.module.bicep' = {
  name: 'devops-project-02-vnet-flow-logs'
  scope: resourceGroup(networkWatcherResourceGroupName)
  params: {
    networkWatcherName: networkWatcherName
    virtualNetworkResourceIds: virtualNetworkResourceIds
    storageAccountResourceId: storageAccountResourceId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    logAnalyticsWorkspaceRegion: logAnalyticsWorkspaceRegion
    retentionDays: retentionDays
  }
}
