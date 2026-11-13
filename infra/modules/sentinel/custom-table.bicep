targetScope = 'resourceGroup'

param workspaceName string
param tableName string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource table 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
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

output tableName string = table.name
