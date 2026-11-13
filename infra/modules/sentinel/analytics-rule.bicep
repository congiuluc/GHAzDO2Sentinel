targetScope = 'resourceGroup'

param workspaceName string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource analyticsRule 'Microsoft.SecurityInsights/alertRules@2023-02-01' = {
  name: guid(workspace.id, 'ghas-active-secret-alert')
  scope: workspace
  kind: 'Scheduled'
  properties: {
    displayName: 'GHAS active secret alert'
    description: 'Creates a Sentinel incident when GHAS reports a newly created or backfilled active secret alert.'
    severity: 'High'
    enabled: true
    query: loadTextContent('../../../sentinel/analytics-rule.kql')
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
