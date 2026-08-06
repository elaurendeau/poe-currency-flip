package com.poeflipfinder.backend.usecase.getingestionfreshness;

import java.time.Instant;

public record IngestionFreshnessResponseModel(Long lastProcessedChangeId, Instant activeGenerationRefreshedAt) {
}
