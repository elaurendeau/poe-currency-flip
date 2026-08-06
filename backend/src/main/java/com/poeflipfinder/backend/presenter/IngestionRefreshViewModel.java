package com.poeflipfinder.backend.presenter;

/** JSON-ready shape for the result of one manual refresh call. */
public record IngestionRefreshViewModel(
        int hoursProcessed,
        boolean fullyCaughtUp,
        Long lastProcessedChangeId,
        int skippedUnresolvableMarketEntryCount) {
}
