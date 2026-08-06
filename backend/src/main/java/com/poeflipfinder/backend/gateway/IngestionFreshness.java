package com.poeflipfinder.backend.gateway;

import java.time.Instant;

/**
 * The ingestion checkpoint/staleness state. Both fields null means ingestion
 * has never completed a successful run. Serves both the interactor's
 * checkpoint read and the freshness-read use case -- one read model, two
 * callers.
 */
public record IngestionFreshness(Long lastProcessedChangeId, Instant activeGenerationRefreshedAt) {
}
