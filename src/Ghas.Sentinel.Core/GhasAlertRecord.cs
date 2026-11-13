using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ghas.Sentinel.Core;

public sealed record GhasAlertRecord
{
    [JsonPropertyName("TimeGenerated")]
    public DateTimeOffset TimeGenerated { get; init; }

    [JsonPropertyName("EventId")]
    public required string EventId { get; init; }

    [JsonPropertyName("EventType")]
    public string? EventType { get; init; }

    [JsonPropertyName("EventAction")]
    public required string EventAction { get; init; }

    [JsonPropertyName("OrganizationUrl")]
    public string? OrganizationUrl { get; init; }

    [JsonPropertyName("ProjectId")]
    public string? ProjectId { get; init; }

    [JsonPropertyName("ProjectName")]
    public string? ProjectName { get; init; }

    [JsonPropertyName("RepositoryName")]
    public required string RepositoryName { get; init; }

    [JsonPropertyName("RepositoryUrl")]
    public required string RepositoryUrl { get; init; }

    [JsonPropertyName("GitRef")]
    public string? GitRef { get; init; }

    [JsonPropertyName("AlertId")]
    public long AlertId { get; init; }

    [JsonPropertyName("AlertType")]
    public string? AlertType { get; init; }

    [JsonPropertyName("Severity")]
    public string? Severity { get; init; }

    [JsonPropertyName("Title")]
    public string? Title { get; init; }

    [JsonPropertyName("State")]
    public string? State { get; init; }

    [JsonPropertyName("ToolName")]
    public string? ToolName { get; init; }

    [JsonPropertyName("RuleId")]
    public string? RuleId { get; init; }

    [JsonPropertyName("RuleName")]
    public string? RuleName { get; init; }

    [JsonPropertyName("RuleHelp")]
    public string? RuleHelp { get; init; }

    [JsonPropertyName("IntroducedDate")]
    public DateTimeOffset? IntroducedDate { get; init; }

    [JsonPropertyName("FirstSeenDate")]
    public DateTimeOffset? FirstSeenDate { get; init; }

    [JsonPropertyName("LastSeenDate")]
    public DateTimeOffset? LastSeenDate { get; init; }

    [JsonPropertyName("FixedDate")]
    public DateTimeOffset? FixedDate { get; init; }

    [JsonPropertyName("DismissalType")]
    public string? DismissalType { get; init; }

    [JsonPropertyName("DismissalMessage")]
    public string? DismissalMessage { get; init; }

    [JsonPropertyName("StateChangedBy")]
    public string? StateChangedBy { get; init; }

    [JsonPropertyName("AlertUrl")]
    public required string AlertUrl { get; init; }

    [JsonPropertyName("PhysicalLocations")]
    public JsonElement? PhysicalLocations { get; init; }

    [JsonPropertyName("LogicalLocations")]
    public JsonElement? LogicalLocations { get; init; }

    [JsonPropertyName("Tools")]
    public JsonElement? Tools { get; init; }

    [JsonPropertyName("RawEvent")]
    public JsonElement? RawEvent { get; init; }
}
