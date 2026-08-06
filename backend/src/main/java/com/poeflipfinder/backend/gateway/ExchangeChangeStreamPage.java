package com.poeflipfinder.backend.gateway;

import java.util.List;

/** One page of the Currency Exchange change-stream, crossing the ExchangeSourceGateway seam. */
public record ExchangeChangeStreamPage(List<ExchangeMarketEntry> entries, long nextChangeId, boolean atTip) {
}
