using System.Text.Json;
using Ghas.Sentinel.Core;

namespace Ghas.Sentinel.Tests;

public sealed class AlertNormalizerTests
{
    [Fact]
    public void Normalize_MapsCreatedEventAndExcludesSensitiveOptionalFieldsByDefault()
    {
        const string payload = """
        {
          "id": "event-123",
          "eventType": "ms.vss-alerts.alert-created-event",
          "createdDate": "2026-10-01T10:00:00Z",
          "resourceContainers": {
            "account": { "baseUrl": "https://dev.azure.com/contoso" },
            "project": { "id": "project-1" }
          },
          "resource": {
            "alertId": 123,
            "alertType": "secret",
            "severity": "high",
            "state": "active",
            "title": "Secret scanning alert",
            "repositoryUrl": "https://dev.azure.com/contoso/Security/_git/app",
            "gitRef": "refs/heads/main",
            "truncatedSecret": "do-not-ingest",
            "physicalLocations": [{ "filePath": "src/key.txt", "snippet": "sensitive-line" }],
            "logicalLocations": [{ "name": "package" }],
            "tools": [{ "name": "secret-scanner", "rules": [{ "opaqueId": "rule-1", "friendlyName": "Rule" }] }]
          }
        }
        """;

        var record = AlertNormalizer.Normalize(payload);
        var serialized = JsonSerializer.Serialize(record);

        Assert.Equal("Created", record.EventAction);
        Assert.Equal("event-123", record.EventId);
        Assert.Equal("Security", record.ProjectName);
        Assert.Equal("app", record.RepositoryName);
        Assert.Equal("https://dev.azure.com/contoso/Security/_git/app/alerts/123", record.AlertUrl);
        Assert.Null(record.PhysicalLocations);
        Assert.Null(record.LogicalLocations);
        Assert.Null(record.RawEvent);
        Assert.DoesNotContain("do-not-ingest", serialized, StringComparison.Ordinal);
        Assert.DoesNotContain("sensitive-line", serialized, StringComparison.Ordinal);
        Assert.Equal("secret-scanner", record.ToolName);
    }

    [Fact]
    public void Normalize_MapsStateChangedEvent()
    {
        const string payload = """
        {
          "id": "event-456",
          "eventType": "ms.vss-alerts.alert-state-changed-event",
          "resource": {
            "alertId": 456,
            "repositoryUrl": "https://dev.azure.com/contoso/Security/_git/app",
            "state": "dismissed"
          }
        }
        """;

        var record = AlertNormalizer.Normalize(payload);

        Assert.Equal("StateChanged", record.EventAction);
        Assert.Equal("dismissed", record.State);
    }

    [Fact]
    public void InitialLoadEnvelope_IsStableAndNeverCopiesTruncatedSecret()
    {
        using var alert = JsonDocument.Parse("""
        {
          "alertId": 7,
          "alertType": "secret",
          "state": "active",
          "repositoryUrl": "https://dev.azure.com/contoso/Security/_git/app",
          "truncatedSecret": "masked-value",
          "additionalInformationMessage": "possible sensitive detail",
          "physicalLocations": [{ "filePath": "src/a.txt" }]
        }
        """);

        var first = InitialLoadEnvelopeFactory.Create(
            alert.RootElement,
            "https://dev.azure.com/contoso",
            "project-1",
            "Security",
            "repo-1");
        var second = InitialLoadEnvelopeFactory.Create(
            alert.RootElement,
            "https://dev.azure.com/contoso",
            "project-1",
            "Security",
            "repo-1");
        using var parsed = JsonDocument.Parse(first);
        using var parsedSecond = JsonDocument.Parse(second);
        var normalized = AlertNormalizer.Normalize(first);

        Assert.Equal(
            parsed.RootElement.GetProperty("id").GetString(),
            parsedSecond.RootElement.GetProperty("id").GetString());
        Assert.Equal("InitialLoad", normalized.EventAction);
        Assert.Null(normalized.PhysicalLocations);
        Assert.DoesNotContain("masked-value", first, StringComparison.Ordinal);
        Assert.DoesNotContain("possible sensitive detail", first, StringComparison.Ordinal);
        Assert.DoesNotContain("physicalLocations", first, StringComparison.Ordinal);
        Assert.StartsWith("initialload-", parsed.RootElement.GetProperty("id").GetString());
    }

    [Fact]
    public void InitialLoadEnvelope_RejectsClosedAlerts()
    {
        using var alert = JsonDocument.Parse("""
        {
          "alertId": 7,
          "state": "dismissed",
          "repositoryUrl": "https://dev.azure.com/contoso/Security/_git/app"
        }
        """);

        Assert.Throws<InvalidDataException>(() => InitialLoadEnvelopeFactory.Create(
            alert.RootElement,
            "https://dev.azure.com/contoso",
            "project-1",
            "Security",
            "repo-1"));
    }
}
