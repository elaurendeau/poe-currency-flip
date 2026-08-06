package com.poeflipfinder.backend.usecase.runingestioncatchup;

public record RunIngestionCatchupResponseModel(
        int hoursProcessed,
        boolean fullyCaughtUp,
        Long lastProcessedChangeId,
        int skippedUnresolvableMarketEntryCount) {
}
