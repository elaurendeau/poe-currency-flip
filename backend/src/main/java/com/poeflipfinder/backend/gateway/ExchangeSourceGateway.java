package com.poeflipfinder.backend.gateway;

/**
 * Defined by the use-case ring for whatever it needs from GGG's Currency
 * Exchange change-stream (docs/ARCHITECTURE.md § Currency Exchange
 * Ingestion). The interactor calls this without knowing whether the
 * implementation is the real GGG API or a test double.
 */
public interface ExchangeSourceGateway {

    /**
     * Fetches one hour of raw market activity. Reaching the current,
     * still-open hour is signaled by ExchangeChangeStreamPage.atTip() -- see
     * docs/DATA_SOURCES.md § Currency Exchange Data for the verified signal.
     */
    ExchangeChangeStreamPage fetchHour(long changeId);
}
