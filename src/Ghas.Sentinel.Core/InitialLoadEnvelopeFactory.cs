using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Ghas.Sentinel.Core;

public static class InitialLoadEnvelopeFactory
{
    private static readonly string[] AlertFields =
    [
        "alertId",
        "alertType",
        "severity",
        "title",
        "state",
        "gitRef",
        "repositoryUrl",
        "introducedDate",
        "firstSeenDate",
        "lastSeenDate",
        "fixedDate",
        "dismissal",
        "tools"
    ];

    public static string Create(
        JsonElement alert,
        string organizationUrl,
        string projectId,
        string projectName,
        string repositoryId,
        bool includeLocations = false)
    {
        var alertId = alert.TryGetProperty("alertId", out var alertIdElement) &&
                      alertIdElement.TryGetInt64(out var parsedAlertId)
            ? parsedAlertId
            : throw new InvalidDataException("The alert is missing its alertId.");
        var repositoryUrl = alert.TryGetProperty("repositoryUrl", out var repositoryUrlElement)
            ? repositoryUrlElement.GetString()
            : null;

        if (string.IsNullOrWhiteSpace(repositoryUrl))
        {
            throw new InvalidDataException("The alert is missing its repositoryUrl.");
        }

        if (!string.Equals(
                alert.TryGetProperty("state", out var state) ? state.GetString() : null,
                "Active",
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Initial load accepts only active alerts.");
        }

        var resource = new JsonObject();
        foreach (var field in AlertFields)
        {
            if (alert.TryGetProperty(field, out var value) && value.ValueKind != JsonValueKind.Null)
            {
                resource[field] = JsonNode.Parse(value.GetRawText());
            }
        }

        if (includeLocations)
        {
            CopyIfPresent(alert, resource, "physicalLocations");
            CopyIfPresent(alert, resource, "logicalLocations");
        }

        var gitRef = alert.TryGetProperty("gitRef", out var gitRefElement)
            ? gitRefElement.GetString()
            : null;
        var eventId = CreateEventId(projectId, repositoryId, alertId, gitRef);

        var envelope = new JsonObject
        {
            ["id"] = eventId,
            ["eventType"] = "ghas.initial-load",
            ["eventAction"] = "InitialLoad",
            ["createdDate"] = DateTimeOffset.UtcNow,
            ["resourceContainers"] = new JsonObject
            {
                ["account"] = new JsonObject { ["baseUrl"] = organizationUrl },
                ["project"] = new JsonObject { ["id"] = projectId, ["name"] = projectName }
            },
            ["resource"] = resource
        };

        return envelope.ToJsonString();
    }

    public static string CreateEventId(string projectId, string repositoryId, long alertId, string? gitRef)
    {
        var input = $"{projectId}|{repositoryId}|{alertId}|{gitRef ?? string.Empty}";
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input)));
        return $"initialload-{hash}";
    }

    private static void CopyIfPresent(JsonElement source, JsonObject destination, string propertyName)
    {
        if (source.TryGetProperty(propertyName, out var value) && value.ValueKind != JsonValueKind.Null)
        {
            destination[propertyName] = JsonNode.Parse(value.GetRawText());
        }
    }
}
