targetScope = 'resourceGroup'

param namespaceName string
param queueName string
param sendAuthorizationRuleName string = 'sendOnly'

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: namespaceName
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBus
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
    name: sendAuthorizationRuleName
    properties: {
      rights: [
        'Send'
      ]
    }
  }
}

output queueName string = queue.name
output sendAuthorizationRule string = queue::sendOnly.name
output resourceId string = queue.id
