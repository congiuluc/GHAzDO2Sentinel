targetScope = 'resourceGroup'

param namespaceName string
param queueName string
param roleDefinitionId string
param identityResourceId string
param principalId string

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: namespaceName
  resource queue 'queues' existing = {
    name: queueName
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus::queue.id, identityResourceId, roleDefinitionId)
  scope: serviceBus::queue
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
