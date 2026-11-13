targetScope = 'resourceGroup'

param name string
param location string
param privateNetworkingEnabled bool = false
param allowPublicAccess bool = true

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  sku: {
    name: privateNetworkingEnabled ? 'Premium' : 'Standard'
    tier: privateNetworkingEnabled ? 'Premium' : 'Standard'
    capacity: privateNetworkingEnabled ? 1 : 0
  }
  properties: {
    minimumTlsVersion: '1.2'
    disableLocalAuth: false
    publicNetworkAccess: allowPublicAccess ? 'Enabled' : 'Disabled'
  }
}

output namespaceName string = serviceBus.name
output resourceId string = serviceBus.id
