targetScope = 'resourceGroup'

param name string
param location string
param queueName string
param identityResourceId string
param identityPrincipalId string
param workspaceResourceId string

var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    disableLocalAuth: false
  }
  resource queue 'queues' = {
    name: queueName
    properties: {
      lockDuration: 'PT5M'
      maxDeliveryCount: 10
      defaultMessageTimeToLive: 'P14D'
      deadLetteringOnMessageExpiration: true
      requiresDuplicateDetection: true
      duplicateDetectionHistoryTimeWindow: 'PT10M'
    }
    resource sendOnly 'authorizationRules' = {
      name: 'sendOnly'
      properties: {
        rights: [
          'Send'
        ]
      }
    }
  }
}

resource serviceBusReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus::queue.id, identityResourceId, serviceBusDataReceiverRoleId)
  scope: serviceBus::queue
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource serviceBusDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'servicebus-to-sentinel'
  scope: serviceBus
  properties: {
    workspaceId: workspaceResourceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output namespaceName string = serviceBus.name
output queueName string = queueName
output sendAuthorizationRule string = 'sendOnly'
