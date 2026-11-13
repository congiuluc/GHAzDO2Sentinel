targetScope = 'resourceGroup'

param name string
param location string

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: name
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Disabled'
    }
  }
}

output resourceId string = dce.id
output logsIngestionEndpoint string = dce.properties.logsIngestion.endpoint
