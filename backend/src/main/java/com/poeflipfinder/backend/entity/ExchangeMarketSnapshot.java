package com.poeflipfinder.backend.entity;

import java.time.Instant;

/**
 * Normalized hourly market data for one currency pair, per docs/SCHEMA.md.
 * Current-state only -- no history is retained; see the hot-swap generation
 * model in docs/ARCHITECTURE.md § Currency Exchange Ingestion.
 */
public record ExchangeMarketSnapshot(
        Long id,
        long generationId,
        League league,
        Currency currencyA,
        Currency currencyB,
        Instant snapshotHour,
        long volumeTradedA,
        long volumeTradedB,
        long lowestStockA,
        long highestStockA,
        long lowestStockB,
        long highestStockB,
        double lowestRatioA,
        double highestRatioA,
        double lowestRatioB,
        double highestRatioB) {
}
