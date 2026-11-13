targetScope = 'resourceGroup'

param name string
param location string
param privateNetworkingEnabled bool = false

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: privateNetworkingEnabled ? true : null
    softDeleteRetentionInDays: 7
    publicNetworkAccess: privateNetworkingEnabled ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: privateNetworkingEnabled ? 'Deny' : 'Allow'
      bypass: 'None'
    }
  }
}

output vaultName string = keyVault.name
output resourceId string = keyVault.id
