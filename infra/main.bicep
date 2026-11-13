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

@sealed()
type privateDnsZones = {
  @minLength(1)
  blob: string
  @minLength(1)
  queue: string
  @minLength(1)
  table: string
  @minLength(1)
  serviceBus: string
  @minLength(1)
  keyVault: string
  @minLength(1)
  sites: string
}

@sealed()
type privateNetworkConfiguration = {
  @minLength(1)
  functionIntegrationSubnetId: string
  @minLength(1)
  privateEndpointSubnetId: string
  @minLength(1)
  monitorPrivateLinkScopeResourceId: string
  privateDnsZoneResourceIds: privateDnsZones
  @description('Explicit exception for Azure DevOps Services hooks. Exposes the authenticated Service Bus public endpoint.')
  allowPublicServiceBusAccess: bool?
}

@description('Optional existing hub-spoke integration. Null preserves the public deployment. Subnets, DNS zones and AMPLS must already exist.')
param privateNetwork privateNetworkConfiguration?

var privateNetworkingEnabled = privateNetwork != null
var suffix = toLower(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName))
var storageAccountName = 'st${take(suffix, 20)}'
var functionAppName = 'func-${take(suffix, 18)}'
var serviceBusName = 'sb-${take(suffix, 18)}'
var identityName = 'id-${take(suffix, 18)}'
var appInsightsName = 'appi-${take(suffix, 18)}'
var keyVaultName = 'kv-${take(suffix, 20)}'
var deploymentContainerName = 'function-packages'
var queueName = 'ghas'

var storageRoleDefinitionIds = [
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
]
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
var dataPrivateEndpointDefinitions = [
  { key: 'storage-blob', target: 'storage', groupId: 'blob', dnsZone: 'blob' }
  { key: 'storage-queue', target: 'storage', groupId: 'queue', dnsZone: 'queue' }
  { key: 'storage-table', target: 'storage', groupId: 'table', dnsZone: 'table' }
  { key: 'servicebus', target: 'serviceBus', groupId: 'namespace', dnsZone: 'serviceBus' }
  { key: 'keyvault', target: 'keyVault', groupId: 'vault', dnsZone: 'keyVault' }
]
var privateEndpointTargets = {
  storage: storage.outputs.resourceId
  serviceBus: serviceBusNamespace.outputs.resourceId
  keyVault: keyVault.outputs.resourceId
}
var monitorPrivateLinkScopeSegments = split(privateNetwork.?monitorPrivateLinkScopeResourceId ?? '', '/')
var monitorPrivateLinkScopeSubscriptionId = privateNetworkingEnabled ? monitorPrivateLinkScopeSegments[2] : subscription().subscriptionId
var monitorPrivateLinkScopeResourceGroup = privateNetworkingEnabled ? monitorPrivateLinkScopeSegments[4] : resourceGroup().name
var monitorPrivateLinkScopeName = last(monitorPrivateLinkScopeSegments)

// Identity

module identity './modules/identity/user-assigned-identity.bicep' = {
  name: 'ghas-identity-${suffix}'
  params: {
    name: identityName
    location: location
  }
}

// Storage

module storage './modules/storage/storage-account.bicep' = {
  name: 'ghas-storage-${suffix}'
  params: {
    name: storageAccountName
    location: location
    deploymentContainerName: deploymentContainerName
    privateNetworkingEnabled: privateNetworkingEnabled
  }
}

module storageRoleAssignments './modules/storage/storage-role-assignment.bicep' = [for roleDefinitionId in storageRoleDefinitionIds: {
  name: 'ghas-storage-role-${take(roleDefinitionId, 8)}-${suffix}'
  params: {
    storageAccountName: storage.outputs.accountName
    roleDefinitionId: roleDefinitionId
    identityResourceId: identity.outputs.resourceId
    principalId: identity.outputs.principalId
  }
}]

// Monitoring

module monitoring './modules/monitoring/application-insights.bicep' = {
  name: 'ghas-monitoring-${suffix}'
  params: {
    name: appInsightsName
    location: location
    workspaceResourceId: workspace.outputs.workspaceId
    privateNetworkingEnabled: privateNetworkingEnabled
  }
}

// Messaging

module serviceBusNamespace './modules/messaging/service-bus-namespace.bicep' = {
  name: 'ghas-servicebus-${suffix}'
  params: {
    name: serviceBusName
    location: location
    privateNetworkingEnabled: privateNetworkingEnabled
    allowPublicAccess: !privateNetworkingEnabled || (privateNetwork.?allowPublicServiceBusAccess ?? false)
  }
}

module serviceBusQueue './modules/messaging/service-bus-queue.bicep' = {
  name: 'ghas-servicebus-queue-${suffix}'
  params: {
    namespaceName: serviceBusNamespace.outputs.namespaceName
    queueName: queueName
  }
}

module serviceBusQueueReceiver './modules/messaging/service-bus-queue-role-assignment.bicep' = {
  name: 'ghas-servicebus-receiver-${suffix}'
  params: {
    namespaceName: serviceBusNamespace.outputs.namespaceName
    queueName: serviceBusQueue.outputs.queueName
    roleDefinitionId: serviceBusDataReceiverRoleId
    identityResourceId: identity.outputs.resourceId
    principalId: identity.outputs.principalId
  }
}

module serviceBusDiagnostics './modules/messaging/service-bus-diagnostics.bicep' = {
  name: 'ghas-servicebus-diagnostics-${suffix}'
  params: {
    namespaceName: serviceBusNamespace.outputs.namespaceName
    workspaceResourceId: workspace.outputs.workspaceId
  }
}

// Security

module keyVault './modules/security/key-vault.bicep' = {
  name: 'ghas-keyvault-${suffix}'
  params: {
    name: keyVaultName
    location: location
    privateNetworkingEnabled: privateNetworkingEnabled
  }
}

// Compute

module functionPlan './modules/compute/flex-consumption-plan.bicep' = {
  name: 'ghas-function-plan-${suffix}'
  params: {
    name: 'plan-${take(suffix, 18)}'
    location: location
  }
}

module functionApp './modules/compute/function-app.bicep' = {
  name: 'ghas-function-${suffix}'
  params: {
    name: functionAppName
    location: location
    planResourceId: functionPlan.outputs.resourceId
    identityResourceId: identity.outputs.resourceId
    identityClientId: identity.outputs.clientId
    storageAccountName: storage.outputs.accountName
    deploymentContainerName: storage.outputs.containerName
    serviceBusNamespaceName: serviceBusNamespace.outputs.namespaceName
    queueName: serviceBusQueue.outputs.queueName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    logsIngestionEndpoint: workspace.outputs.logsIngestionEndpoint
    dcrImmutableId: workspace.outputs.dcrImmutableId
    maximumInstanceCount: maximumInstanceCount
    instanceMemoryMB: instanceMemoryMB
    integrationSubnetId: privateNetwork.?functionIntegrationSubnetId ?? ''
  }
  dependsOn: [
    storageRoleAssignments
    serviceBusQueueReceiver
    dataPrivateEndpoints
    dcePrivateLink
    appInsightsPrivateLink
  ]
}

// Sentinel workspace (existing, possibly in another subscription)

module workspace './workspace.bicep' = {
  name: 'ghas-sentinel-workspace'
  scope: resourceGroup(workspaceSubscriptionId, workspaceResourceGroup)
  params: {
    workspaceName: workspaceName
    workspaceRegion: workspaceRegion
    environmentName: environmentName
    ingestionPrincipalId: identity.outputs.principalId
    enableAnalyticsRule: enableAnalyticsRule == 'true'
    privateNetworkingEnabled: privateNetworkingEnabled
  }
}

// Optional private networking (existing hub & spoke)

module dataPrivateEndpoints './modules/networking/private-endpoint.bicep' = [for endpoint in dataPrivateEndpointDefinitions: if (privateNetworkingEnabled) {
  name: 'ghas-pe-${endpoint.key}-${suffix}'
  params: {
    name: 'pe-${endpoint.key}-${suffix}'
    location: location
    subnetId: privateNetwork!.privateEndpointSubnetId
    privateLinkServiceId: privateEndpointTargets[endpoint.target]
    groupId: endpoint.groupId
    privateDnsZoneId: privateNetwork!.privateDnsZoneResourceIds[endpoint.dnsZone]
  }
}]

module functionPrivateEndpoint './modules/networking/private-endpoint.bicep' = if (privateNetworkingEnabled) {
  name: 'ghas-pe-function-${suffix}'
  params: {
    name: 'pe-function-${suffix}'
    location: location
    subnetId: privateNetwork!.privateEndpointSubnetId
    privateLinkServiceId: functionApp.outputs.resourceId
    groupId: 'sites'
    privateDnsZoneId: privateNetwork!.privateDnsZoneResourceIds.sites
  }
}

module dcePrivateLink './modules/networking/monitor-private-link-scoped-resource.bicep' = if (privateNetworkingEnabled) {
  name: 'ghas-ampls-dce-${suffix}'
  scope: resourceGroup(monitorPrivateLinkScopeSubscriptionId, monitorPrivateLinkScopeResourceGroup)
  params: {
    scopeName: monitorPrivateLinkScopeName
    linkedResourceId: workspace.outputs.dataCollectionEndpointResourceId
  }
}

// AMPLS scoped resources are serialized to avoid concurrent updates on the shared scope.
module appInsightsPrivateLink './modules/networking/monitor-private-link-scoped-resource.bicep' = if (privateNetworkingEnabled) {
  name: 'ghas-ampls-appi-${suffix}'
  scope: resourceGroup(monitorPrivateLinkScopeSubscriptionId, monitorPrivateLinkScopeResourceGroup)
  params: {
    scopeName: monitorPrivateLinkScopeName
    linkedResourceId: monitoring.outputs.resourceId
  }
  dependsOn: [
    dcePrivateLink
  ]
}

output functionAppName string = functionApp.outputs.name
output serviceBusNamespace string = serviceBusNamespace.outputs.namespaceName
output serviceBusQueueName string = serviceBusQueue.outputs.queueName
output serviceBusSendAuthorizationRule string = serviceBusQueue.outputs.sendAuthorizationRule
output keyVaultName string = keyVault.outputs.vaultName
output managedIdentityClientId string = identity.outputs.clientId
output workspaceResourceId string = workspace.outputs.workspaceId
