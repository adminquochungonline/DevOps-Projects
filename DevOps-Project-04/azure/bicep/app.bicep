// =============================================================================
// Application layer - Azure equivalent of "ECS task definition + service + ALB"
// =============================================================================
// Deployed after the image is pushed to ACR. Container Apps bundles the task
// definition, the service, the load balancer (Envoy ingress) and the autoscaler
// into a single resource.
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region. Must match the Container Apps environment.')
param location string = resourceGroup().location

@minLength(3)
@maxLength(12)
@description('Lowercase prefix used for resource names.')
param prefix string = 'devops04'

@description('Resource ID of the Container Apps environment from platform.bicep.')
param environmentId string

@description('Resource ID of the user-assigned managed identity from platform.bicep.')
param managedIdentityId string

@description('Login server of the registry, e.g. myregistry.azurecr.io.')
param registryLoginServer string

@description('Fully qualified image reference, e.g. myregistry.azurecr.io/django-app:1.0.0. Avoid :latest so revisions stay traceable.')
param containerImage string

@secure()
@minLength(32)
@description('Django SECRET_KEY. Source it from Key Vault or a pipeline secret, never from source control.')
param djangoSecretKey string

@description('Comma separated Django ALLOWED_HOSTS. Narrow this to the ingress FQDN (and custom domains) once known.')
param allowedHosts string = '*'

@description('Comma separated CSRF_TRUSTED_ORIGINS, e.g. https://app.contoso.com. Required for POST forms behind a custom domain.')
param csrfTrustedOrigins string = ''

@description('Port the container listens on.')
param targetPort int = 8000

@description('vCPU per replica. Consumption profile allows 0.25 - 4 in 0.25 steps, paired with 0.5 GiB per 0.25 vCPU.')
param cpu string = '0.5'

@description('Memory per replica, paired with the cpu value.')
param memory string = '1Gi'

@minValue(0)
@maxValue(300)
@description('Minimum replicas. 0 enables scale-to-zero (cheapest, adds cold start); 1 keeps a warm replica; 2+ survives a single replica failure.')
param minReplicas int = 1

@minValue(1)
@maxValue(300)
@description('Maximum replicas the HTTP autoscaler may create.')
param maxReplicas int = 10

@minValue(1)
@description('Concurrent requests per replica that trigger scale-out.')
param concurrentRequests int = 50

@description('Expose the app to the internet. Set false to keep ingress internal to the environment/VNet.')
param externalIngress bool = true

@description('Tags applied to all resources.')
param tags object = {
  project: 'DevOps-Project-04'
  workload: 'django-hello-world'
  deployment: 'azure-container-apps'
}

var appName = '${prefix}-django-app'

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        // NOTE: external ingress publishes this app on a public FQDN with no
        // authentication in front of it. For anything beyond a demo, enable
        // Container Apps authentication (Entra ID) or front it with Azure
        // Front Door / Application Gateway + WAF.
        external: externalIngress
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          // Pull via managed identity: no registry credentials stored.
          server: registryLoginServer
          identity: managedIdentityId
        }
      ]
      secrets: [
        {
          name: 'django-secret-key'
          value: djangoSecretKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'django'
          image: containerImage
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            {
              name: 'DJANGO_SETTINGS_MODULE'
              value: 'hello_world_django_app.settings_azure'
            }
            {
              name: 'DJANGO_ALLOWED_HOSTS'
              value: allowedHosts
            }
            {
              name: 'DJANGO_CSRF_TRUSTED_ORIGINS'
              value: csrfTrustedOrigins
            }
            {
              name: 'PORT'
              value: string(targetPort)
            }
            {
              name: 'DJANGO_SECRET_KEY'
              secretRef: 'django-secret-key'
            }
          ]
          probes: [
            {
              // failureThreshold is capped at 10 by the Container Apps API, so
              // the startup budget comes from the interval: 10 x 6s = 60s.
              type: 'Startup'
              httpGet: {
                path: '/health/'
                port: targetPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 6
              timeoutSeconds: 3
              failureThreshold: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health/'
                port: targetPort
                scheme: 'HTTP'
              }
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/'
                port: targetPort
                scheme: 'HTTP'
              }
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: string(concurrentRequests)
              }
            }
          }
        ]
      }
    }
  }
}

output appName string = containerApp.name
output appFqdn string = containerApp.properties.configuration.ingress.fqdn
output appUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output latestRevisionName string = containerApp.properties.latestRevisionName
