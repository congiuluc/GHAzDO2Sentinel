namespace Ghas.Sentinel.Core;

public sealed record AlertNormalizerOptions(
    bool IncludeLocations = false,
    bool IncludeRawEvent = false);
