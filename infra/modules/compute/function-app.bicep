targetScope = 'resourceGroup'

param name string
param location string
param planResourceId string
param identityResourceId string
param identityClientId string
param storageAccountName string
param deploymentContainerName string
param serviceBusNamespaceName string
param queueName string
param applicationInsightsName string
param logsIngestionEndpoint string
param dcrImmutableId string
param maximumInstanceCount int
param instanceMemoryMB int
param integrationSubnetId string = ''

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    serverFarmId: planResourceId
    httpsOnly: true
    publicNetworkAccess: empty(integrationSubnetId) ? 'Enabled' : 'Disabled'
    virtualNetworkSubnetId: empty(integrationSubnetId) ? null : integrationSubnetId
    siteConfig: {
      minTlsVersion: '1.2'
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/${deploymentContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityResourceId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '10'
      }
    }
  }
  resource appSettings 'config' = {
    name: 'appsettings'
    properties: {
      AzureWebJobsStorage__accountName: storageAccountName
      AzureWebJobsStorage__credential: 'managedidentity'
      AzureWebJobsStorage__clientId: identityClientId
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
      AzureCredentialMode: 'ManagedIdentity'
      ManagedIdentityClientId: identityClientId
      QueueName: queueName
      ServiceBusConnection__fullyQualifiedNamespace: '${serviceBusNamespaceName}.servicebus.windows.net'
      ServiceBusConnection__credential: 'managedidentity'
      ServiceBusConnection__clientId: identityClientId
      LogsIngestion__Endpoint: logsIngestionEndpoint
      LogsIngestion__DcrImmutableId: dcrImmutableId
      LogsIngestion__StreamName: 'Custom-GHASAlerts_CL'
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
      Privacy__IncludeLocations: 'false'
      Privacy__IncludeRawEvent: 'false'
    }
  }
}

output name string = functionApp.name
output resourceId string = functionApp.id
