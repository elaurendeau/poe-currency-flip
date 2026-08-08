package com.poeflipfinder.backend.framework.exchange;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.poeflipfinder.backend.gateway.ExchangeChangeStreamPage;
import com.poeflipfinder.backend.gateway.ExchangeMarketEntry;
import com.poeflipfinder.backend.gateway.ExchangeSourceGateway;
import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * The Frameworks & Drivers implementation of ExchangeSourceGateway, calling
 * GGG's public Currency Exchange change-stream (docs/DATA_SOURCES.md §
 * Currency Exchange Data). This is the Anti-Corruption Layer boundary:
 * everything above this class only ever sees ExchangeMarketEntry, never this
 * class's Raw* shapes.
 *
 * <p>Reaching the current, still-open hour is signaled by an HTTP 404 whose
 * body echoes the requested change id back with an empty markets array --
 * verified by direct testing 2026-08-06, not a failure.
 */
public class GggExchangeSourceGateway implements ExchangeSourceGateway {

    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    public GggExchangeSourceGateway(RestClient.Builder restClientBuilder) {
        this.restClient = restClientBuilder.baseUrl("https://web.poecdn.com").build();
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public ExchangeChangeStreamPage fetchHour(long changeId) {
        try {
            String json = restClient
                    .get()
                    .uri("/api/currency-exchange/{changeId}", changeId)
                    .retrieve()
                    .body(String.class);
            return normalize(json, changeId, false);
        } catch (HttpClientErrorException.NotFound e) {
            return normalize(e.getResponseBodyAsString(), changeId, true);
        } catch (RestClientException e) {
            throw new ExchangeSourceGatewayException("Failed to fetch Currency Exchange hour " + changeId, e);
        }
    }

    /**
     * Public so contract and integration tests can exercise real parsing
     * against a saved fixture without a live HTTP call -- including tests
     * outside this package that need real-data-through-real-parsing, e.g.
     * DivinationCardOpportunityFinderIntegrationTest.
     */
    public ExchangeChangeStreamPage normalize(String json, long requestedChangeId, boolean atTip) {
        RawPage rawPage = deserialize(json);
        Instant snapshotHour = Instant.ofEpochSecond(requestedChangeId);
        List<ExchangeMarketEntry> entries =
                rawPage.markets().stream().map(raw -> toEntry(raw, snapshotHour)).toList();
        return new ExchangeChangeStreamPage(entries, rawPage.nextChangeId(), atTip);
    }

    private RawPage deserialize(String json) {
        try {
            return objectMapper.readValue(json, RawPage.class);
        } catch (IOException e) {
            throw new ExchangeSourceGatewayException("Failed to parse Currency Exchange response", e);
        }
    }

    private ExchangeMarketEntry toEntry(RawMarket raw, Instant snapshotHour) {
        String a = raw.marketPair().get(0);
        String b = raw.marketPair().get(1);
        return new ExchangeMarketEntry(
                raw.league(),
                a,
                b,
                snapshotHour,
                longValue(raw.volumeTraded(), a),
                longValue(raw.volumeTraded(), b),
                longValue(raw.lowestStock(), a),
                longValue(raw.highestStock(), a),
                longValue(raw.lowestStock(), b),
                longValue(raw.highestStock(), b),
                doubleValue(raw.lowestRatio(), a),
                doubleValue(raw.highestRatio(), a),
                doubleValue(raw.lowestRatio(), b),
                doubleValue(raw.highestRatio(), b));
    }

    private long longValue(Map<String, Long> valuesByItemPath, String itemPath) {
        return valuesByItemPath.getOrDefault(itemPath, 0L);
    }

    private double doubleValue(Map<String, Double> valuesByItemPath, String itemPath) {
        return valuesByItemPath.getOrDefault(itemPath, 0.0);
    }

    // ignoreUnknown so fields GGG adds later (e.g. market_id, which we
    // recompute from market_pair rather than store) never break parsing.
    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawPage(@JsonProperty("next_change_id") long nextChangeId, List<RawMarket> markets) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawMarket(
            String league,
            @JsonProperty("market_pair") List<String> marketPair,
            @JsonProperty("volume_traded") Map<String, Long> volumeTraded,
            @JsonProperty("lowest_stock") Map<String, Long> lowestStock,
            @JsonProperty("highest_stock") Map<String, Long> highestStock,
            @JsonProperty("lowest_ratio") Map<String, Double> lowestRatio,
            @JsonProperty("highest_ratio") Map<String, Double> highestRatio) {
    }
}
