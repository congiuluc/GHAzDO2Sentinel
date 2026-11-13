targetScope = 'resourceGroup'

param name string
param location string
param workspaceResourceId string
param streamName string
@description('Optional data collection endpoint; empty uses the DCR direct ingestion endpoint.')
param dataCollectionEndpointId string = ''

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: name
  location: location
  kind: 'Direct'
  properties: {
    dataCollectionEndpointId: empty(dataCollectionEndpointId) ? null : dataCollectionEndpointId
    streamDeclarations: {
      '${streamName}': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'EventId', type: 'string' }
          { name: 'EventType', type: 'string' }
          { name: 'EventAction', type: 'string' }
          { name: 'OrganizationUrl', type: 'string' }
          { name: 'ProjectId', type: 'string' }
          { name: 'ProjectName', type: 'string' }
          { name: 'RepositoryName', type: 'string' }
          { name: 'RepositoryUrl', type: 'string' }
          { name: 'GitRef', type: 'string' }
          { name: 'AlertId', type: 'long' }
          { name: 'AlertType', type: 'string' }
          { name: 'Severity', type: 'string' }
          { name: 'Title', type: 'string' }
          { name: 'State', type: 'string' }
          { name: 'ToolName', type: 'string' }
          { name: 'RuleId', type: 'string' }
          { name: 'RuleName', type: 'string' }
          { name: 'RuleHelp', type: 'string' }
          { name: 'IntroducedDate', type: 'datetime' }
          { name: 'FirstSeenDate', type: 'datetime' }
          { name: 'LastSeenDate', type: 'datetime' }
          { name: 'FixedDate', type: 'datetime' }
          { name: 'DismissalType', type: 'string' }
          { name: 'DismissalMessage', type: 'string' }
          { name: 'StateChangedBy', type: 'string' }
          { name: 'AlertUrl', type: 'string' }
          { name: 'PhysicalLocations', type: 'dynamic' }
          { name: 'LogicalLocations', type: 'dynamic' }
          { name: 'Tools', type: 'dynamic' }
          { name: 'RawEvent', type: 'dynamic' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          name: 'sentinelWorkspace'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          streamName
        ]
        destinations: [
          'sentinelWorkspace'
        ]
        outputStream: streamName
        transformKql: 'source'
      }
    ]
  }
}

output name string = dcr.name
output resourceId string = dcr.id
output immutableId string = dcr.properties.immutableId
output logsIngestionEndpoint string = dcr.properties.endpoints.logsIngestion
