package com.poeflipfinder.backend.framework.league;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.LeagueGateway;
import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import org.springframework.web.client.RestClient;

/**
 * The Frameworks & Drivers implementation of LeagueGateway, calling GGG's
 * public Leagues API (docs/DATA_SOURCES.md § League List). This is the
 * Anti-Corruption Layer boundary: everything above this class only ever
 * sees League entities, never this class's Raw* shapes.
 */
public class GggLeagueGateway implements LeagueGateway {

    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    public GggLeagueGateway(RestClient.Builder restClientBuilder) {
        this.restClient = restClientBuilder.baseUrl("https://api.pathofexile.com").build();
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public List<League> fetchLeagues() {
        String json = restClient.get().uri("/leagues").retrieve().body(String.class);
        return normalize(json);
    }

    /** Package-visible so the contract test can exercise parsing without a live HTTP call. */
    List<League> normalize(String json) {
        RawLeague[] rawLeagues = deserialize(json);
        return Arrays.stream(rawLeagues)
                .filter(raw -> !isSoloSelfFound(raw))
                .map(this::toEntity)
                .toList();
    }

    private RawLeague[] deserialize(String json) {
        try {
            return objectMapper.readValue(json, RawLeague[].class);
        } catch (IOException e) {
            throw new LeagueGatewayException("Failed to parse Leagues API response", e);
        }
    }

    private boolean isSoloSelfFound(RawLeague raw) {
        return hasRule(raw, "NoParties");
    }

    private League toEntity(RawLeague raw) {
        // hasExchangeActivity is not yet cross-checked against ingested market data
        // (docs/ARCHITECTURE.md § League Resolution step 3) -- wired in once the
        // Currency Exchange ingestion service exists.
        return new League(null, raw.id(), raw.name(), isMainlineCurrentChallengeLeague(raw), false);
    }

    // GGG flags every ruleset variant of the active challenge (softcore,
    // Hardcore, Ruthless, ...) with the same category.current=true, so that
    // flag alone matches more than one league -- only the plain variant with
    // no modifying rules is "the" mainline default from docs/PRD.md § 7.4.
    private boolean isMainlineCurrentChallengeLeague(RawLeague raw) {
        boolean isCurrentCategory = raw.category() != null && Boolean.TRUE.equals(raw.category().current());
        return isCurrentCategory && !hasRule(raw, "Hardcore") && !hasRule(raw, "HardMode");
    }

    private boolean hasRule(RawLeague raw, String ruleId) {
        return raw.rules() != null && raw.rules().stream().anyMatch(rule -> ruleId.equals(rule.id()));
    }

    // ignoreUnknown so fields GGG adds later (or ones we simply don't need,
    // e.g. realm/url/startAt) never break parsing -- only a field we
    // actually read being renamed or removed should ever fail this adapter.
    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawLeague(String id, String name, RawCategory category, List<RawRule> rules) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawCategory(String id, Boolean current) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawRule(String id, String name, String description) {
    }
}
