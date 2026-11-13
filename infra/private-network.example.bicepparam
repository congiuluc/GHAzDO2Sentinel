using './main.bicep'

param environmentName = 'private-example'
param location = 'westeurope'
param workspaceSubscriptionId = '00000000-0000-0000-0000-000000000000'
param workspaceResourceGroup = 'rg-sentinel'
param workspaceName = 'law-sentinel'
param workspaceRegion = 'westeurope'
param enableAnalyticsRule = 'true'

var networkSubscriptionId = '00000000-0000-0000-0000-000000000000'
var spokeId = '/subscriptions/${networkSubscriptionId}/resourceGroups/rg-spoke/providers/Microsoft.Network/virtualNetworks/vnet-spoke'
var dnsZonePrefix = '/subscriptions/${networkSubscriptionId}/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones'

param privateNetwork = {
  functionIntegrationSubnetId: '${spokeId}/subnets/snet-functions'
  privateEndpointSubnetId: '${spokeId}/subnets/snet-private-endpoints'
  monitorPrivateLinkScopeResourceId: '/subscriptions/${networkSubscriptionId}/resourceGroups/rg-monitor/providers/Microsoft.Insights/privateLinkScopes/ampls-hub'
  privateDnsZoneResourceIds: {
    blob: '${dnsZonePrefix}/privatelink.blob.core.windows.net'
    queue: '${dnsZonePrefix}/privatelink.queue.core.windows.net'
    table: '${dnsZonePrefix}/privatelink.table.core.windows.net'
    serviceBus: '${dnsZonePrefix}/privatelink.servicebus.windows.net'
    keyVault: '${dnsZonePrefix}/privatelink.vaultcore.azure.net'
    sites: '${dnsZonePrefix}/privatelink.azurewebsites.net'
  }
  allowPublicServiceBusAccess: false
}
