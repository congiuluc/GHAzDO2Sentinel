targetScope = 'resourceGroup'

param name string
param location string
param deploymentContainerName string
param privateNetworkingEnabled bool = false

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: privateNetworkingEnabled ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: privateNetworkingEnabled ? 'Deny' : 'Allow'
      bypass: 'None'
    }
  }
  resource blobServices 'blobServices' = {
    name: 'default'
    resource deploymentContainer 'containers' = {
      name: deploymentContainerName
      properties: {
        publicAccess: 'None'
      }
    }
  }
}

output accountName string = storage.name
output containerName string = storage::blobServices::deploymentContainer.name
output resourceId string = storage.id
