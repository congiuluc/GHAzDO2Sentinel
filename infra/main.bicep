targetScope = 'resourceGroup'

@description('Primary deployment region for application resources.')
param location string = resourceGroup().location

@description('AZD environment name used to create unique resource names.')
@minLength(1)
param environmentName string

@description('Subscription containing the existing Microsoft Sentinel workspace.')
param workspaceSubscriptionId string

@description('Resource group containing the existing Microsoft Sentinel workspace.')
param workspaceResourceGroup string

@description('Name of the existing Microsoft Sentinel Log Analytics workspace.')
param workspaceName string

@description('Region of the existing workspace; the DCR must be deployed in this region.')
param workspaceRegion string

@description('Create the optional GHAS secret-alert analytics rule.')
@allowed(['true', 'false'])
param enableAnalyticsRule string = 'true'

@description('Maximum Flex Consumption instance count.')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 40

@description('Memory size, in MB, for each Flex Consumption instance.')
@allowed([2048, 4096])
param instanceMemoryMB int = 2048

var suffix = toLower(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName))
var storageAccountName = 'st${take(suffix, 20)}'
var functionAppName = 'func-${take(suffix, 18)}'
var serviceBusName = 'sb-${take(suffix, 18)}'
var identityName = 'id-${take(suffix, 18)}'
var appInsightsName = 'appi-${take(suffix, 18)}'
var keyVaultName = 'kv-${take(suffix, 20)}'
var deploymentContainerName = 'function-packages'
var queueName = 'ghas'

module identity './modules/identity.bicep' = {
  name: 'ghas-identity-${suffix}'
  params: {
    name: identityName
    location: location
  }
}

module storage './modules/storage.bicep' = {
  name: 'ghas-storage-${suffix}'
  params: {
    name: storageAccountName
    location: location
    deploymentContainerName: deploymentContainerName
    identityResourceId: identity.outputs.resourceId
    identityPrincipalId: identity.outputs.principalId
  }
}

module monitoring './modules/monitoring.bicep' = {
  name: 'ghas-monitoring-${suffix}'
  params: {
    name: appInsightsName
    location: location
    workspaceResourceId: workspace.outputs.workspaceId
  }
}

module serviceBus './modules/service-bus.bicep' = {
  name: 'ghas-servicebus-${suffix}'
  params: {
    name: serviceBusName
    location: location
    queueName: queueName
    identityResourceId: identity.outputs.resourceId
    identityPrincipalId: identity.outputs.principalId
    workspaceResourceId: workspace.outputs.workspaceId
  }
}

module functionApp './modules/function.bicep' = {
  name: 'ghas-function-${suffix}'
  params: {
    functionAppName: functionAppName
    planName: 'plan-${take(suffix, 18)}'
    location: location
    identityResourceId: identity.outputs.resourceId
    identityClientId: identity.outputs.clientId
    storageAccountName: storage.outputs.accountName
    deploymentContainerName: storage.outputs.containerName
    serviceBusNamespaceName: serviceBus.outputs.namespaceName
    queueName: serviceBus.outputs.queueName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    logsIngestionEndpoint: workspace.outputs.logsIngestionEndpoint
    dcrImmutableId: workspace.outputs.dcrImmutableId
    maximumInstanceCount: maximumInstanceCount
    instanceMemoryMB: instanceMemoryMB
  }
}

module keyVault './modules/key-vault.bicep' = {
  name: 'ghas-keyvault-${suffix}'
  params: {
    name: keyVaultName
    location: location
  }
}

module workspace './workspace.bicep' = {
  name: 'ghas-sentinel-workspace'
  scope: resourceGroup(workspaceSubscriptionId, workspaceResourceGroup)
  params: {
    workspaceName: workspaceName
    workspaceRegion: workspaceRegion
    environmentName: environmentName
    ingestionPrincipalId: identity.outputs.principalId
    enableAnalyticsRule: enableAnalyticsRule == 'true'
  }
}

output functionAppName string = functionApp.outputs.name
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output serviceBusQueueName string = serviceBus.outputs.queueName
output serviceBusSendAuthorizationRule string = serviceBus.outputs.sendAuthorizationRule
output keyVaultName string = keyVault.outputs.vaultName
output managedIdentityClientId string = identity.outputs.clientId
output workspaceResourceId string = workspace.outputs.workspaceId
