// =============================================================================
// Platform layer - Azure equivalent of "ECR + ECS cluster + CloudWatch + IAM"
// =============================================================================
// Deployed once, before the application image exists:
//   Azure Container Registry      <- Amazon ECR
//   Container Apps Environment    <- ECS cluster (Fargate capacity)
//   Log Analytics workspace       <- CloudWatch Logs
//   User-assigned managed identity + AcrPull  <- ecsTaskExecutionRole
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for every resource in this deployment.')
param location string = resourceGroup().location

@minLength(3)
@maxLength(12)
@description('Lowercase prefix used for resource names.')
param prefix string = 'devops04'

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
@description('Container Registry SKU. Premium is required for private endpoints, geo-replication and content trust.')
param acrSku string = 'Basic'

@minValue(30)
@maxValue(730)
@description('Log Analytics retention in days.')
param logRetentionInDays int = 30

@description('Tags applied to all resources.')
param tags object = {
  project: 'DevOps-Project-04'
  workload: 'django-hello-world'
  deployment: 'azure-container-apps'
}

// ACR names are globally unique and alphanumeric only.
var registryName = take('acr${toLower(replace(prefix, '-', ''))}${uniqueString(resourceGroup().id)}', 50)
var workspaceName = '${prefix}-law'
var environmentName = '${prefix}-cae'
var identityName = '${prefix}-app-identity'

// AcrPull built-in role definition.
var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    // Pull happens through managed identity + RBAC, so the shared admin
    // account stays disabled (no long-lived registry password anywhere).
    // Anonymous pull is off by default on this API version and is not enabled
    // here; every pull is authenticated.
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    retentionInDays: logRetentionInDays
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// Least privilege: pull only, scoped to this registry.
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, 'AcrPull')
  scope: registry
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output registryName string = registry.name
output registryLoginServer string = registry.properties.loginServer
output environmentId string = managedEnvironment.id
output environmentName string = managedEnvironment.name
output identityId string = identity.id
output identityClientId string = identity.properties.clientId
output workspaceName string = workspace.name
output workspaceCustomerId string = workspace.properties.customerId
