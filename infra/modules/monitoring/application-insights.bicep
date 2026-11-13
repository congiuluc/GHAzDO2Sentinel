targetScope = 'resourceGroup'

param name string
param location string
param workspaceResourceId string
param privateNetworkingEnabled bool = false

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceResourceId
    publicNetworkAccessForIngestion: privateNetworkingEnabled ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: privateNetworkingEnabled ? 'Disabled' : 'Enabled'
  }
}

output applicationInsightsName string = applicationInsights.name
output resourceId string = applicationInsights.id
