targetScope = 'resourceGroup'

@description('Azure region. Choose a region that supports Availability Zones for the selected VM SKU.')
param location string = resourceGroup().location

@minLength(2)
@maxLength(12)
@description('Lowercase prefix used for resource names.')
param prefix string = 'devops02'

@description('Administrator username for VMSS instances.')
param adminUsername string = 'azureadmin'

@secure()
@description('SSH public key. Password authentication is disabled.')
param sshPublicKey string

@description('Resource ID of the Ubuntu image version in Azure Compute Gallery.')
param galleryImageVersionId string

@description('VM size available in the selected region and zones.')
param vmSku string = 'Standard_B1ms'

@minValue(2)
@maxValue(4)
param vmssDefaultCapacity int = 2

@minValue(2)
@maxValue(4)
param vmssMaximumCapacity int = 4

@description('Availability Zones used by VMSS. Adjust for region support.')
param availabilityZones array = [
  '1'
  '2'
  '3'
]

@description('Repository cloned by VMSS bootstrap.')
param siteRepositoryUrl string = 'https://github.com/adminquochungonline/DevOps-Projects.git'

@description('Git branch or tag cloned by VMSS bootstrap.')
param siteRepositoryRef string = 'master'

@description('Website path inside the repository.')
param siteSourcePath string = 'DevOps-Project-02/html-web-app'

@description('Optional Azure DNS zone to create. Leave empty to use the Application Gateway public IP FQDN only.')
param dnsZoneName string = ''

param managementVnetPrefix string = '192.168.0.0/16'
param bastionSubnetPrefix string = '192.168.1.0/26'
param applicationVnetPrefix string = '172.20.0.0/16'
param applicationGatewaySubnetPrefix string = '172.20.1.0/24'
param applicationSubnetPrefix string = '172.20.10.0/24'

var managementVnetName = '${prefix}-management-vnet'
var applicationVnetName = '${prefix}-application-vnet'
var vmssName = '${prefix}-vmss'
var storageAccountName = take('stg${toLower(replace('${prefix}${uniqueString(resourceGroup().id)}', '-', ''))}', 24)
var configContainerName = 'app-config'
var blobReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
var bootstrapEnvironment = '#!/usr/bin/env bash\nexport SITE_REPOSITORY_URL=\'${siteRepositoryUrl}\'\nexport SITE_REPOSITORY_REF=\'${siteRepositoryRef}\'\nexport SITE_SOURCE_PATH=\'${siteSourcePath}\'\nexport STORAGE_ACCOUNT_NAME=\'${storageAccountName}\'\nexport CONFIG_CONTAINER_NAME=\'${configContainerName}\'\nexport MANAGED_IDENTITY_CLIENT_ID=\'${vmssIdentity.properties.clientId}\'\n'
var bootstrapData = '${bootstrapEnvironment}${loadTextContent('bootstrap.sh')}'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-law'
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: applicationSubnet.id
        }
      ]
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource configContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: configContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource vmssIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-vmss-identity'
  location: location
}

resource blobReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(configContainer.id, vmssIdentity.id, blobReaderRoleDefinitionId)
  scope: configContainer
  properties: {
    principalId: vmssIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: blobReaderRoleDefinitionId
  }
}

resource appNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-app-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-AppGateway-HTTP'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          protocol: 'Tcp'
          sourceAddressPrefix: applicationGatewaySubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'Allow-Bastion-SSH'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 110
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Deny-Other-VNet-Inbound'
        properties: {
          access: 'Deny'
          direction: 'Inbound'
          priority: 200
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource natPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: '${prefix}-nat'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
  }
}

resource managementVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: managementVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        managementVnetPrefix
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

resource applicationVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: applicationVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        applicationVnetPrefix
      ]
    }
    subnets: [
      {
        name: 'application-gateway-subnet'
        properties: {
          addressPrefix: applicationGatewaySubnetPrefix
        }
      }
      {
        name: 'application-subnet'
        properties: {
          addressPrefix: applicationSubnetPrefix
          natGateway: {
            id: natGateway.id
          }
          networkSecurityGroup: {
            id: appNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
    ]
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: managementVnet
  name: 'AzureBastionSubnet'
}

resource appGatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: applicationVnet
  name: 'application-gateway-subnet'
}

resource applicationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: applicationVnet
  name: 'application-subnet'
}

resource managementToApplication 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: managementVnet
  name: 'management-to-application'
  properties: {
    allowForwardedTraffic: true
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: applicationVnet.id
    }
  }
}

resource applicationToManagement 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: applicationVnet
  name: 'application-to-management'
  properties: {
    allowForwardedTraffic: true
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: managementVnet.id
    }
  }
}

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: '${prefix}-bastion'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ip-config'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: bastionPublicIp.id
          }
          subnet: {
            id: bastionSubnet.id
          }
        }
      }
    ]
  }
}

resource appGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-appgw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    dnsSettings: {
      domainNameLabel: toLower('${prefix}-${uniqueString(resourceGroup().id)}')
    }
    publicIPAllocationMethod: 'Static'
  }
}

resource applicationGateway 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: '${prefix}-appgw'
  location: location
  properties: {
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 4
    }
    backendAddressPools: [
      {
        name: 'vmss-backend-pool'
        properties: {}
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'http-settings'
        properties: {
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          port: 80
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', '${prefix}-appgw', 'health-probe')
          }
          protocol: 'Http'
          requestTimeout: 30
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'public-frontend'
        properties: {
          publicIPAddress: {
            id: appGatewayPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'http-port'
        properties: {
          port: 80
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'gateway-ip-config'
        properties: {
          subnet: {
            id: appGatewaySubnet.id
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', '${prefix}-appgw', 'public-frontend')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', '${prefix}-appgw', 'http-port')
          }
          protocol: 'Http'
        }
      }
    ]
    probes: [
      {
        name: 'health-probe'
        properties: {
          interval: 30
          path: '/healthz'
          pickHostNameFromBackendHttpSettings: true
          protocol: 'Http'
          timeout: 10
          unhealthyThreshold: 3
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'default-route'
        properties: {
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', '${prefix}-appgw', 'vmss-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', '${prefix}-appgw', 'http-settings')
          }
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', '${prefix}-appgw', 'http-listener')
          }
          priority: 100
          ruleType: 'Basic'
        }
      }
    ]
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
  }
}

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-07-01' = {
  name: vmssName
  location: location
  zones: availabilityZones
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${vmssIdentity.id}': {}
    }
  }
  sku: {
    capacity: vmssDefaultCapacity
    name: vmSku
    tier: 'Standard'
  }
  dependsOn: [
    blobReaderAssignment
  ]
  properties: {
    orchestrationMode: 'Uniform'
    overprovision: true
    singlePlacementGroup: false
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      extensionProfile: {
        extensions: [
          {
            name: 'ConfigureApplication'
            properties: {
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              protectedSettings: {
                script: base64(bootstrapData)
              }
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
            }
          }
          {
            name: 'AzureMonitorLinuxAgent'
            properties: {
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              publisher: 'Microsoft.Azure.Monitor'
              type: 'AzureMonitorLinuxAgent'
              typeHandlerVersion: '1.33'
            }
          }
        ]
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${prefix}-nic'
            properties: {
              enableAcceleratedNetworking: false
              ipConfigurations: [
                {
                  name: 'ip-config'
                  properties: {
                    applicationGatewayBackendAddressPools: [
                      {
                        id: applicationGateway.properties.backendAddressPools[0].id
                      }
                    ]
                    primary: true
                    subnet: {
                      id: applicationSubnet.id
                    }
                  }
                }
              ]
              primary: true
            }
          }
        ]
      }
      osProfile: {
        adminUsername: adminUsername
        computerNamePrefix: take(prefix, 9)
        linuxConfiguration: {
          disablePasswordAuthentication: true
          provisionVMAgent: true
          ssh: {
            publicKeys: [
              {
                keyData: sshPublicKey
                path: '/home/${adminUsername}/.ssh/authorized_keys'
              }
            ]
          }
        }
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      storageProfile: {
        imageReference: {
          id: galleryImageVersionId
        }
        osDisk: {
          caching: 'ReadWrite'
          createOption: 'FromImage'
          diskSizeGB: 30
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
    }
  }
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${prefix}-linux-dcr'
  location: location
  kind: 'Linux'
  properties: {
    dataFlows: [
      {
        destinations: [
          'central-workspace'
        ]
        streams: [
          'Microsoft-Perf'
          'Microsoft-Syslog'
        ]
      }
    ]
    dataSources: {
      performanceCounters: [
        {
          counterSpecifiers: [
            '\\Memory\\Available MBytes'
            '\\Memory\\% Used Memory'
            '\\Processor(_Total)\\% Processor Time'
          ]
          name: 'linux-performance'
          samplingFrequencyInSeconds: 60
          streams: [
            'Microsoft-Perf'
          ]
        }
      ]
      syslog: [
        {
          facilityNames: [
            '*'
          ]
          logLevels: [
            '*'
          ]
          name: 'linux-syslog'
          streams: [
            'Microsoft-Syslog'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'central-workspace'
          workspaceResourceId: logAnalytics.id
        }
      ]
    }
  }
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: '${prefix}-vmss-dcr-association'
  scope: vmss
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
    description: 'Collect VMSS Linux syslog, memory, and CPU telemetry.'
  }
}

resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${prefix}-vmss-autoscale'
  location: location
  properties: {
    enabled: true
    name: '${prefix}-vmss-autoscale'
    profiles: [
      {
        name: 'cpu-based-scaling'
        capacity: {
          default: string(vmssDefaultCapacity)
          maximum: string(vmssMaximumCapacity)
          minimum: '2'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'microsoft.compute/virtualmachinescalesets'
              metricResourceUri: vmss.id
              operator: 'GreaterThan'
              statistic: 'Average'
              threshold: 70
              timeAggregation: 'Average'
              timeGrain: 'PT1M'
              timeWindow: 'PT5M'
            }
            scaleAction: {
              cooldown: 'PT5M'
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'microsoft.compute/virtualmachinescalesets'
              metricResourceUri: vmss.id
              operator: 'LessThan'
              statistic: 'Average'
              threshold: 30
              timeAggregation: 'Average'
              timeGrain: 'PT1M'
              timeWindow: 'PT10M'
            }
            scaleAction: {
              cooldown: 'PT5M'
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
            }
          }
        ]
      }
    ]
    targetResourceUri: vmss.id
  }
}

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' = if (!empty(dnsZoneName)) {
  name: dnsZoneName
  location: 'global'
}

resource dnsRootRecord 'Microsoft.Network/dnsZones/A@2018-05-01' = if (!empty(dnsZoneName)) {
  parent: dnsZone
  name: '@'
  properties: {
    ARecords: [
      {
        ipv4Address: appGatewayPublicIp.properties.ipAddress
      }
    ]
    TTL: 300
  }
}

output applicationUrl string = 'http://${appGatewayPublicIp.properties.dnsSettings.fqdn}'
output customDomainUrl string = !empty(dnsZoneName) ? 'http://${dnsZoneName}' : ''
output applicationGatewayPublicIp string = appGatewayPublicIp.properties.ipAddress
output bastionName string = bastion.name
output configStorageAccountName string = storage.name
output vmssManagedIdentityClientId string = vmssIdentity.properties.clientId
output logAnalyticsWorkspaceId string = logAnalytics.id
output managementVnetId string = managementVnet.id
output applicationVnetId string = applicationVnet.id
output dnsNameServers array = !empty(dnsZoneName) ? dnsZone!.properties.nameServers : []
