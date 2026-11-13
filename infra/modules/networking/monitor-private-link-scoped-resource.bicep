targetScope = 'resourceGroup'

@description('Name of the existing Azure Monitor Private Link Scope (AMPLS).')
param scopeName string
param linkedResourceId string

resource privateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' existing = {
  name: scopeName
}

resource scopedResource 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: privateLinkScope
  name: 'ghas-${uniqueString(linkedResourceId)}'
  properties: {
    linkedResourceId: linkedResourceId
  }
}
