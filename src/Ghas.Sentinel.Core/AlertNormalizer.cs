using System.Globalization;
using System.Text.Json;

namespace Ghas.Sentinel.Core;

public static class AlertNormalizer
{
    public static GhasAlertRecord Normalize(
        string json,
        AlertNormalizerOptions? options = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);
        options ??= new AlertNormalizerOptions();

        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var resource = GetObject(root, "resource")
            ?? throw new InvalidDataException("The event is missing its resource object.");

        var eventType = GetString(root, "eventType");
        var eventAction = GetString(root, "eventAction") ?? GetEventAction(eventType);
        var eventId = GetString(root, "id");
        if (string.IsNullOrWhiteSpace(eventId))
        {
            throw new InvalidDataException("The event is missing its id.");
        }

        var repositoryUrl = GetString(resource, "repositoryUrl");
        if (string.IsNullOrWhiteSpace(repositoryUrl))
        {
            throw new InvalidDataException("The alert is missing its repositoryUrl.");
        }

        var alertId = GetInt64(resource, "alertId")
            ?? throw new InvalidDataException("The alert is missing its alertId.");
        var (projectName, repositoryName) = ParseRepositoryUrl(repositoryUrl);
        var containers = GetObject(root, "resourceContainers");
        var account = containers is { } containerElement ? GetObject(containerElement, "account") : null;
        var project = containers is { } containersElement ? GetObject(containersElement, "project") : null;
        var tools = GetArrayItem(resource, "tools", 0);
        var rules = tools is { } toolElement ? GetArrayItem(toolElement, "rules", 0) : null;
        var dismissal = GetObject(resource, "dismissal");

        return new GhasAlertRecord
        {
            TimeGenerated = GetDateTime(root, "createdDate") ?? DateTimeOffset.UtcNow,
            EventId = eventId,
            EventType = eventType,
            EventAction = eventAction,
            OrganizationUrl = account is { } accountElement
                ? GetString(accountElement, "baseUrl") ?? GetOrganizationUrl(repositoryUrl)
                : GetOrganizationUrl(repositoryUrl),
            ProjectId = project is { } projectElement
                ? GetString(projectElement, "id") ?? GetString(resource, "projectId")
                : GetString(resource, "projectId"),
            ProjectName = projectName,
            RepositoryName = repositoryName,
            RepositoryUrl = repositoryUrl,
            GitRef = GetString(resource, "gitRef"),
            AlertId = alertId,
            AlertType = GetString(resource, "alertType"),
            Severity = GetString(resource, "severity"),
            Title = GetString(resource, "title"),
            State = GetString(resource, "state"),
            ToolName = tools is { } tool ? GetString(tool, "name") : null,
            RuleId = rules is { } rule ? GetString(rule, "opaqueId") : null,
            RuleName = rules is { } ruleName ? GetString(ruleName, "friendlyName") : null,
            RuleHelp = rules is { } ruleHelp ? GetString(ruleHelp, "helpMessage") : null,
            IntroducedDate = GetDateTime(resource, "introducedDate"),
            FirstSeenDate = GetDateTime(resource, "firstSeenDate"),
            LastSeenDate = GetDateTime(resource, "lastSeenDate"),
            FixedDate = GetDateTime(resource, "fixedDate"),
            DismissalType = dismissal is { } dismissalType ? GetString(dismissalType, "dismissalType") : null,
            DismissalMessage = dismissal is { } dismissalMessage ? GetString(dismissalMessage, "message") : null,
            StateChangedBy = dismissal is { } changedBy
                ? GetIdentityValue(changedBy, "stateChangedBy")
                : null,
            AlertUrl = $"{repositoryUrl.TrimEnd('/')}/alerts/{alertId}",
            PhysicalLocations = options.IncludeLocations ? Clone(resource, "physicalLocations") : null,
            LogicalLocations = options.IncludeLocations ? Clone(resource, "logicalLocations") : null,
            Tools = Clone(resource, "tools"),
            RawEvent = options.IncludeRawEvent ? root.Clone() : null
        };
    }

    public static string GetEventAction(string? eventType) => eventType switch
    {
        "ms.vss-alerts.alert-created-event" => "Created",
        "ms.vss-alerts.alert-state-changed-event" => "StateChanged",
        "ms.vss-alerts.alert-updated-event" => "Updated",
        "ghas.initial-load" => "InitialLoad",
        _ => "Unknown"
    };

    private static string GetIdentityValue(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var value))
        {
            return string.Empty;
        }

        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString() ?? string.Empty,
            JsonValueKind.Object => GetString(value, "id") ?? GetString(value, "displayName") ?? string.Empty,
            _ => string.Empty
        };
    }

    private static (string? ProjectName, string RepositoryName) ParseRepositoryUrl(string repositoryUrl)
    {
        if (!Uri.TryCreate(repositoryUrl, UriKind.Absolute, out var uri))
        {
            throw new InvalidDataException("The alert repositoryUrl is not an absolute URI.");
        }

        var segments = uri.AbsolutePath
            .Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.UnescapeDataString)
            .ToArray();
        var gitIndex = Array.FindIndex(segments, segment =>
            string.Equals(segment, "_git", StringComparison.OrdinalIgnoreCase));

        if (gitIndex < 1 || gitIndex + 1 >= segments.Length)
        {
            throw new InvalidDataException("The alert repositoryUrl does not contain an Azure Repos _git path.");
        }

        return (segments[gitIndex - 1], segments[gitIndex + 1]);
    }

    private static string? GetOrganizationUrl(string repositoryUrl)
    {
        if (!Uri.TryCreate(repositoryUrl, UriKind.Absolute, out var uri))
        {
            return null;
        }

        var segments = uri.AbsolutePath
            .Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.UnescapeDataString)
            .ToArray();

        if (uri.Host.Equals("dev.azure.com", StringComparison.OrdinalIgnoreCase) && segments.Length > 0)
        {
            return $"{uri.GetLeftPart(UriPartial.Authority)}/{segments[0]}";
        }

        return uri.GetLeftPart(UriPartial.Authority);
    }

    private static JsonElement? Clone(JsonElement parent, string propertyName) =>
        parent.TryGetProperty(propertyName, out var value) && value.ValueKind != JsonValueKind.Null
            ? value.Clone()
            : null;

    private static JsonElement? GetObject(JsonElement parent, string propertyName) =>
        parent.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.Object
            ? value
            : null;

    private static JsonElement? GetArrayItem(JsonElement parent, string propertyName, int index) =>
        parent.TryGetProperty(propertyName, out var value) &&
        value.ValueKind == JsonValueKind.Array &&
        value.GetArrayLength() > index
            ? value[index]
            : null;

    private static string? GetString(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.ToString(),
            _ => null
        };
    }

    private static long? GetInt64(JsonElement parent, string propertyName) =>
        parent.TryGetProperty(propertyName, out var value) && value.TryGetInt64(out var number)
            ? number
            : null;

    private static DateTimeOffset? GetDateTime(JsonElement parent, string propertyName)
    {
        var text = GetString(parent, propertyName);
        return DateTimeOffset.TryParse(
            text,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
            out var result)
            ? result
            : null;
    }
}
