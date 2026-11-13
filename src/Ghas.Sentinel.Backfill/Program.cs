using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Ghas.Sentinel.Core;

var organizationUrl = RequiredEnvironmentVariable("AZDO_ORG_URL").TrimEnd('/');
var projectId = RequiredEnvironmentVariable("AZDO_PROJECT_ID");
var accessToken = RequiredEnvironmentVariable("AZDO_ACCESS_TOKEN");
var serviceBusNamespace = RequiredEnvironmentVariable("SERVICEBUS_FULLY_QUALIFIED_NAMESPACE");
var queueName = Environment.GetEnvironmentVariable("SERVICEBUS_QUEUE_NAME") ?? "GHAS";
var authScheme = Environment.GetEnvironmentVariable("AZDO_AUTH_SCHEME") ?? "Basic";
var includeLocations = string.Equals(
    Environment.GetEnvironmentVariable("GHAS_INCLUDE_LOCATIONS"),
    "true",
    StringComparison.OrdinalIgnoreCase);

if (authScheme is not ("Basic" or "Bearer"))
{
    throw new InvalidOperationException("AZDO_AUTH_SCHEME must be either Basic or Bearer.");
}

var organization = GetOrganizationName(organizationUrl);
var projectName = Environment.GetEnvironmentVariable("AZDO_PROJECT_NAME") ?? projectId;
using var httpClient = new HttpClient();
httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
    authScheme,
    authScheme == "Basic"
        ? Convert.ToBase64String(Encoding.ASCII.GetBytes($":{accessToken}"))
        : accessToken);
httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

var credential = new DefaultAzureCredential();
await using var serviceBusClient = new ServiceBusClient(serviceBusNamespace, credential);
var sender = serviceBusClient.CreateSender(queueName);
var repositoryCount = 0;
var alertCount = 0;

await foreach (var repository in GetRepositoriesAsync(httpClient, organizationUrl, projectId))
{
    repositoryCount++;
    await foreach (var alert in GetActiveAlertsAsync(
                       httpClient,
                       organization,
                       projectId,
                       repository.RepositoryId))
    {
        var envelope = InitialLoadEnvelopeFactory.Create(
            alert,
            organizationUrl,
            projectId,
            projectName,
            repository.RepositoryId,
            includeLocations);
        using var envelopeDocument = JsonDocument.Parse(envelope);
        var eventId = envelopeDocument.RootElement.GetProperty("id").GetString()
            ?? throw new InvalidDataException("Generated initial-load event is missing its id.");

        var message = new ServiceBusMessage(BinaryData.FromString(envelope))
        {
            MessageId = eventId,
            ContentType = "application/json"
        };
        await sender.SendMessageAsync(message);
        alertCount++;
    }
}

Console.WriteLine(
    $"Published {alertCount} active alerts from {repositoryCount} repositories in project {projectName}.");

static string RequiredEnvironmentVariable(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : throw new InvalidOperationException($"Required environment variable {name} is not set.");

static string GetOrganizationName(string organizationUrl)
{
    if (!Uri.TryCreate(organizationUrl, UriKind.Absolute, out var uri) ||
        !uri.Host.Equals("dev.azure.com", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException(
            "AZDO_ORG_URL must use the Azure DevOps Services URL format https://dev.azure.com/{organization}.");
    }

    return uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()
        ?? throw new InvalidOperationException("AZDO_ORG_URL must include an organization name.");
}

static async IAsyncEnumerable<RepositoryInfo> GetRepositoriesAsync(
    HttpClient client,
    string organizationUrl,
    string projectId)
{
    var url = $"{organizationUrl}/{Uri.EscapeDataString(projectId)}/_apis/git/repositories?api-version=7.1";
    using var response = await client.GetAsync(url);
    await EnsureSuccessAsync(response, "listing project repositories");
    using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

    foreach (var repository in document.RootElement.GetProperty("value").EnumerateArray())
    {
        if (repository.TryGetProperty("id", out var id) && id.GetString() is { Length: > 0 } repositoryId)
        {
            yield return new RepositoryInfo(repositoryId);
        }
    }
}

static async IAsyncEnumerable<JsonElement> GetActiveAlertsAsync(
    HttpClient client,
    string organization,
    string projectId,
    string repositoryId)
{
    string? continuationToken = null;
    do
    {
        var query =
            $"criteria.states=Active&criteria.onlyDefaultBranch=false&top=1000&api-version=7.2-preview.1";
        if (!string.IsNullOrEmpty(continuationToken))
        {
            query += $"&continuationToken={Uri.EscapeDataString(continuationToken)}";
        }

        var url =
            $"https://advsec.dev.azure.com/{Uri.EscapeDataString(organization)}/{Uri.EscapeDataString(projectId)}/_apis/alert/repositories/{Uri.EscapeDataString(repositoryId)}/alerts?{query}";
        using var response = await client.GetAsync(url);
        await EnsureSuccessAsync(response, $"listing alerts for repository {repositoryId}");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var page = document.RootElement.GetProperty("value")
            .EnumerateArray()
            .Select(alert => alert.Clone())
            .ToArray();

        foreach (var alert in page)
        {
            if (alert.TryGetProperty("state", out var state) &&
                string.Equals(state.GetString(), "Active", StringComparison.OrdinalIgnoreCase))
            {
                yield return alert;
            }
        }

        continuationToken = response.Headers.TryGetValues("x-ms-continuationtoken", out var values)
            ? values.FirstOrDefault()
            : null;
    } while (!string.IsNullOrWhiteSpace(continuationToken));
}

static async Task EnsureSuccessAsync(HttpResponseMessage response, string operation)
{
    if (!response.IsSuccessStatusCode)
    {
        throw new HttpRequestException(
            $"Azure DevOps returned HTTP {(int)response.StatusCode} while {operation}.");
    }
}

internal sealed record RepositoryInfo(string RepositoryId);
