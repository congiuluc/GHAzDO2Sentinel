using Azure;
using Azure.Messaging.ServiceBus;
using Azure.Monitor.Ingestion;
using Ghas.Sentinel.Core;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace Ghas.Sentinel.Function;

public sealed class ProcessGhasAlert(
    LogsIngestionClient ingestionClient,
    IConfiguration configuration,
    AlertNormalizerOptions normalizerOptions,
    ILogger<ProcessGhasAlert> logger)
{
    [Function(nameof(ProcessGhasAlert))]
    public async Task Run(
        [ServiceBusTrigger("%QueueName%", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        CancellationToken cancellationToken)
    {
        var record = AlertNormalizer.Normalize(message.Body.ToString(), normalizerOptions);
        var dcrImmutableId = configuration["LogsIngestion:DcrImmutableId"];
        var streamName = configuration["LogsIngestion:StreamName"];

        if (string.IsNullOrWhiteSpace(dcrImmutableId) || string.IsNullOrWhiteSpace(streamName))
        {
            throw new InvalidOperationException(
                "LogsIngestion:DcrImmutableId and LogsIngestion:StreamName are required.");
        }

        var data = BinaryData.FromObjectAsJson(new[] { record });
        var response = await ingestionClient.UploadAsync(
            dcrImmutableId,
            streamName,
            new[] { data },
            cancellationToken: cancellationToken).ConfigureAwait(false);

        if (response.IsError)
        {
            throw new InvalidOperationException(
                $"Logs Ingestion API returned HTTP {(int)response.Status} for event {record.EventId}.");
        }

        logger.LogInformation(
            "Ingested GHAS event {EventId} for alert {AlertId} with action {EventAction}.",
            record.EventId,
            record.AlertId,
            record.EventAction);
    }
}
