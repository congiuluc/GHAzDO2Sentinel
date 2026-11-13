targetScope = 'resourceGroup'

param name string
param location string
param workspaceResourceId string

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: name
  location: location
  kind: 'shared'
  properties: {
    category: 'sentinel'
    displayName: 'GitHub Advanced Security alerts'
    description: 'GHAS alert triage with optional ingestion and queue health panels.'
    serializedData: loadTextContent('../../../sentinel/ghas-workbook.json')
    sourceId: workspaceResourceId
    version: '1.0'
  }
}

output resourceId string = workbook.id
