targetScope = 'resourceGroup'

@description('Name of the existing Microsoft Sentinel Log Analytics workspace.')
param workspaceName string

@description('Region of the workspace and its data collection rule.')
param workspaceRegion string

@description('AZD environment name used in resource names.')
param environmentName string

@description('Principal ID granted permission to publish to the DCR.')
param ingestionPrincipalId string

@description('Create the optional GHAS secret-alert analytics rule.')
param enableAnalyticsRule bool

@description('Create a private data collection endpoint for Logs Ingestion API; the existing workspace network policy is not changed.')
param privateNetworkingEnabled bool = false

var suffix = toLower(uniqueString(workspace.id, environmentName))
var tableName = 'GHASAlerts_CL'
var streamName = 'Custom-GHASAlerts_CL'
var publisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

module customTable './modules/sentinel/custom-table.bicep' = {
  name: 'ghas-table-${suffix}'
  params: {
    workspaceName: workspace.name
    tableName: tableName
  }
}

module dataCollectionEndpoint './modules/sentinel/data-collection-endpoint.bicep' = if (privateNetworkingEnabled) {
  name: 'ghas-dce-${suffix}'
  params: {
    name: 'dce-ghas-${suffix}'
    location: workspaceRegion
  }
}

module dataCollectionRule './modules/sentinel/data-collection-rule.bicep' = {
  name: 'ghas-dcr-${suffix}'
  params: {
    name: 'dcr-ghas-${suffix}'
    location: workspaceRegion
    workspaceResourceId: workspace.id
    streamName: streamName
    dataCollectionEndpointId: privateNetworkingEnabled ? dataCollectionEndpoint!.outputs.resourceId : ''
  }
  dependsOn: [
    customTable
  ]
}

module dcrPublisher './modules/sentinel/data-collection-rule-role-assignment.bicep' = {
  name: 'ghas-dcr-publisher-${suffix}'
  params: {
    dataCollectionRuleName: dataCollectionRule.outputs.name
    roleDefinitionId: publisherRoleId
    principalId: ingestionPrincipalId
  }
}

module analyticsRule './modules/sentinel/analytics-rule.bicep' = if (enableAnalyticsRule) {
  name: 'ghas-analytics-rule-${suffix}'
  params: {
    workspaceName: workspace.name
  }
}

module workbook './modules/sentinel/workbook.bicep' = {
  name: 'ghas-workbook-${suffix}'
  params: {
    name: guid(workspace.id, environmentName, 'ghas-workbook')
    location: workspaceRegion
    workspaceResourceId: workspace.id
  }
}

output workspaceId string = workspace.id
output dcrImmutableId string = dataCollectionRule.outputs.immutableId
output logsIngestionEndpoint string = privateNetworkingEnabled ? dataCollectionEndpoint!.outputs.logsIngestionEndpoint : dataCollectionRule.outputs.logsIngestionEndpoint
output dataCollectionEndpointResourceId string = privateNetworkingEnabled ? dataCollectionEndpoint!.outputs.resourceId : ''
output streamName string = streamName
output workbookResourceId string = workbook.outputs.resourceId
