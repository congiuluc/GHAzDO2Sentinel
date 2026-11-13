[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [uri] $OrganizationUrl,

    [Parameter(Mandatory)]
    [string] $ProjectId,

    [Parameter(Mandatory)]
    [string] $NamespaceName,

    [Parameter(Mandatory)]
    [string] $QueueName,

    [Parameter(Mandatory)]
    [ValidateSet('Sas', 'ServiceConnection')]
    [string] $AuthenticationMode,

    [string] $ResourceGroup,

    [string] $ServiceConnectionId,

    [string] $KeyVaultName,

    [string] $KeyVaultSecretName = 'ghas-service-hook-send'
)

$ErrorActionPreference = 'Stop'
$accessToken = [Environment]::GetEnvironmentVariable('AZDO_ACCESS_TOKEN')
if ([string]::IsNullOrWhiteSpace($accessToken)) {
    throw 'Set AZDO_ACCESS_TOKEN to a token with permission to manage project service hooks.'
}

if ($OrganizationUrl.Host -ne 'dev.azure.com' -and
    -not $OrganizationUrl.Host.EndsWith('.visualstudio.com', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OrganizationUrl must be an Azure DevOps Services URL.'
}

$headers = @{
    Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$accessToken")))"
    'Content-Type' = 'application/json'
    Accept = 'application/json'
}

$consumerInputs = @{
    queueName = $QueueName
    bypassSerializer = $true
}

if ($AuthenticationMode -eq 'Sas') {
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
        throw 'ResourceGroup is required for SAS mode so the queue-scoped send key can be retrieved.'
    }

    $connectionString = & az servicebus queue authorization-rule keys list `
        --resource-group $ResourceGroup `
        --namespace-name $NamespaceName `
        --queue-name $QueueName `
        --name sendOnly `
        --query primaryConnectionString `
        --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($connectionString)) {
        throw 'Could not retrieve the queue-scoped send connection string. Check Azure CLI sign-in and permissions.'
    }

    $connectionString = $connectionString -replace ';EntityPath=[^;]*', ''
    $consumerInputs['AuthenticationMechanismInputId'] = 'connectionString'
    $consumerInputs['connectionString'] = $connectionString

    if (-not [string]::IsNullOrWhiteSpace($KeyVaultName)) {
        $vaultToken = & az account get-access-token `
            --resource https://vault.azure.net `
            --query accessToken `
            --output tsv
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($vaultToken)) {
            throw 'Could not acquire an Azure Key Vault access token.'
        }

        $secretUri = "https://$KeyVaultName.vault.azure.net/secrets/$([uri]::EscapeDataString($KeyVaultSecretName))?api-version=7.4"
        $secretBody = @{ value = $connectionString } | ConvertTo-Json -Compress
        $null = Invoke-RestMethod -Method Put -Uri $secretUri -Headers @{
            Authorization = "Bearer $vaultToken"
        } -ContentType 'application/json' -Body $secretBody
        Write-Host "Stored the queue-scoped SAS credential in Key Vault secret '$KeyVaultSecretName'."
    }
}
else {
    if ([string]::IsNullOrWhiteSpace($ServiceConnectionId)) {
        throw 'ServiceConnectionId is required for ServiceConnection mode.'
    }

    $consumerInputs['AuthenticationMechanismInputId'] = 'serviceConnection'
    $consumerInputs['ServiceConnectionInputId'] = $ServiceConnectionId
    $consumerInputs['ServiceBusHostNameInputId'] = "sb://$NamespaceName.servicebus.windows.net"
}

$organizationBase = $OrganizationUrl.AbsoluteUri.TrimEnd('/')
$subscriptionsUri = "$organizationBase/_apis/hooks/subscriptions?api-version=7.1-preview.1"
$subscriptions = (Invoke-RestMethod -Method Get -Uri $subscriptionsUri -Headers $headers).value
$eventTypes = @(
    'ms.vss-alerts.alert-created-event',
    'ms.vss-alerts.alert-state-changed-event',
    'ms.vss-alerts.alert-updated-event'
)

foreach ($eventType in $eventTypes) {
    $existing = $subscriptions | Where-Object {
        $_.publisherId -eq 'advsec' -and
        $_.eventType -eq $eventType -and
        $_.consumerId -eq 'azureServiceBus' -and
        $_.consumerActionId -eq 'serviceBusQueueSend' -and
        $_.publisherInputs.projectId -eq $ProjectId
    } | Select-Object -First 1

    if ($null -ne $existing) {
        if ($existing.consumerInputs.queueName -ne $QueueName) {
            throw "A subscription for '$eventType' already targets another queue (subscription $($existing.id))."
        }

        Write-Host "Already configured: $eventType (subscription $($existing.id))."
        continue
    }

    $body = @{
        publisherId = 'advsec'
        eventType = $eventType
        consumerId = 'azureServiceBus'
        consumerActionId = 'serviceBusQueueSend'
        publisherInputs = @{
            projectId = $ProjectId
        }
        consumerInputs = $consumerInputs
    } | ConvertTo-Json -Depth 10

    $null = Invoke-RestMethod -Method Post -Uri $subscriptionsUri -Headers $headers -Body $body
    Write-Host "Created service hook: $eventType."
}
