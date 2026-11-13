using Azure.Core;
using Azure.Identity;
using Azure.Monitor.Ingestion;
using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Azure.Functions.Worker.OpenTelemetry;
using OpenTelemetry;
using Ghas.Sentinel.Core;

var builder = FunctionsApplication.CreateBuilder(args);

var credentialMode = builder.Configuration["AzureCredentialMode"] ?? "DefaultAzureCredential";
var managedIdentityClientId = builder.Configuration["ManagedIdentityClientId"];
TokenCredential credential = credentialMode switch
{
    "ManagedIdentity" => new ManagedIdentityCredential(
        string.IsNullOrWhiteSpace(managedIdentityClientId)
            ? ManagedIdentityId.SystemAssigned
            : ManagedIdentityId.FromUserAssignedClientId(managedIdentityClientId)),
    "DefaultAzureCredential" => new DefaultAzureCredential(),
    _ => throw new InvalidOperationException(
        "AzureCredentialMode must be ManagedIdentity or DefaultAzureCredential.")
};

var ingestionEndpoint = builder.Configuration["LogsIngestion:Endpoint"];
if (string.IsNullOrWhiteSpace(ingestionEndpoint))
{
    throw new InvalidOperationException("LogsIngestion:Endpoint configuration is required.");
}

builder.Services.AddSingleton(new LogsIngestionClient(new Uri(ingestionEndpoint), credential));
builder.Services.AddSingleton(new AlertNormalizerOptions(
    IncludeLocations: bool.TryParse(builder.Configuration["Privacy:IncludeLocations"], out var includeLocations) &&
                      includeLocations,
    IncludeRawEvent: bool.TryParse(builder.Configuration["Privacy:IncludeRawEvent"], out var includeRawEvent) &&
                    includeRawEvent));

builder.ConfigureFunctionsWebApplication();

if (!string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    builder.Services.AddOpenTelemetry()
        .UseFunctionsWorkerDefaults()
        .UseAzureMonitorExporter();
}

builder.Build().Run();
