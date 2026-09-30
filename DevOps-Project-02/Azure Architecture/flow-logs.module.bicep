targetScope = 'resourceGroup'

param networkWatcherName string
param virtualNetworkResourceIds array
param storageAccountResourceId string
param logAnalyticsWorkspaceResourceId string
param logAnalyticsWorkspaceId string
param logAnalyticsWorkspaceRegion string
param retentionDays int

resource networkWatcher 'Microsoft.Network/networkWatchers@2024-05-01' existing = {
  name: networkWatcherName
}

resource flowLogs 'Microsoft.Network/networkWatchers/flowLogs@2024-05-01' = [for (vnetId, index) in virtualNetworkResourceIds: {
  parent: networkWatcher
  name: 'devops02-vnet-${index + 1}-flowlog'
  location: logAnalyticsWorkspaceRegion
  properties: {
    enabled: true
    targetResourceId: vnetId
    storageId: storageAccountResourceId
    retentionPolicy: {
      days: retentionDays
      enabled: retentionDays > 0
    }
    format: {
      type: 'JSON'
      version: 2
    }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        trafficAnalyticsInterval: 10
        workspaceId: logAnalyticsWorkspaceId
        workspaceRegion: logAnalyticsWorkspaceRegion
        workspaceResourceId: logAnalyticsWorkspaceResourceId
      }
    }
  }
}]
