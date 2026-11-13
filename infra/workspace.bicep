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

var suffix = toLower(uniqueString(workspace.id, environmentName))
var tableName = 'GHASAlerts_CL'
var streamName = 'Custom-GHASAlerts_CL'
var workbookId = guid(workspace.id, environmentName, 'ghas-workbook')
var publisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource ghasTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: tableName
  properties: {
    schema: {
      name: tableName
      columns: [
        { name: 'TimeGenerated', type: 'dateTime' }
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
        { name: 'IntroducedDate', type: 'dateTime' }
        { name: 'FirstSeenDate', type: 'dateTime' }
        { name: 'LastSeenDate', type: 'dateTime' }
        { name: 'FixedDate', type: 'dateTime' }
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
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-ghas-${suffix}'
  location: workspaceRegion
  kind: 'Direct'
  properties: {
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
          workspaceResourceId: workspace.id
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
  dependsOn: [
    ghasTable
  ]
}

resource dcrPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcr.id, ingestionPrincipalId, publisherRoleId)
  scope: dcr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', publisherRoleId)
    principalId: ingestionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource analyticsRule 'Microsoft.SecurityInsights/alertRules@2023-02-01' = if (enableAnalyticsRule) {
  name: guid(workspace.id, 'ghas-active-secret-alert')
  scope: workspace
  kind: 'Scheduled'
  properties: {
    displayName: 'GHAS active secret alert'
    description: 'Creates a Sentinel incident when GHAS reports a newly created or backfilled active secret alert.'
    severity: 'High'
    enabled: true
    query: loadTextContent('../sentinel/analytics-rule.kql')
    queryFrequency: 'PT1H'
    queryPeriod: 'PT1H'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionEnabled: false
    suppressionDuration: 'PT5H'
    tactics: [
      'CredentialAccess'
    ]
    techniques: [
      'T1552'
    ]
    incidentConfiguration: {
      createIncident: true
    }
    eventGroupingSettings: {
      aggregationKind: 'AlertPerResult'
    }
  }
}

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: workbookId
  location: workspaceRegion
  kind: 'shared'
  properties: {
    category: 'sentinel'
    displayName: 'GitHub Advanced Security alerts'
    description: 'GHAS alert triage with optional ingestion and queue health panels.'
    serializedData: loadTextContent('../sentinel/ghas-workbook.json')
    sourceId: workspace.id
    version: '1.0'
  }
}

output workspaceId string = workspace.id
output dcrImmutableId string = dcr.properties.immutableId
output logsIngestionEndpoint string = dcr.properties.endpoints.logsIngestion
output streamName string = streamName
output workbookResourceId string = workbook.id
