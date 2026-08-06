package com.poeflipfinder.backend.gateway;

import java.time.Instant;

/**
 * One normalized-but-not-yet-resolved market entry from the Currency
 * Exchange change-stream -- external ids as raw strings, since resolving
 * them into Currency/League entities is CurrencyReferenceGateway's and
 * LeagueReferenceGateway's job, not this seam's.
 */
public record ExchangeMarketEntry(
        String leagueExternalId,
        String currencyAExternalId,
        String currencyBExternalId,
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
