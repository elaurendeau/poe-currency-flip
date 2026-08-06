package com.poeflipfinder.backend.framework.league;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.entity.League;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

/**
 * Contract test per docs/ARCHITECTURE.md § 3: a saved real API response in,
 * an asserted normalized domain object out. If GGG changes the Leagues API
 * shape, this test breaks with a specific diff pointing at this one file.
 */
class GggLeagueGatewayTest {

    private final GggLeagueGateway gateway = new GggLeagueGateway(RestClient.builder());

    @Test
    void normalize_excludesSoloSelfFoundLeagues() {
        List<League> leagues = gateway.normalize(fixture());

        assertThat(leagues)
                .extracting(League::externalId)
                .containsExactlyInAnyOrder("Standard", "Allflame", "Hardcore Allflame", "Ruthless Allflame")
                .doesNotContain("Solo Self-Found", "SSF Allflame");
    }

    @Test
    void normalize_marksOnlyTheMainlineVariantOfTheCurrentChallengeLeague() {
        List<League> leagues = gateway.normalize(fixture());

        assertThat(findByExternalId(leagues, "Standard").isCurrent()).isFalse();
        assertThat(findByExternalId(leagues, "Allflame").isCurrent()).isTrue();
        assertThat(findByExternalId(leagues, "Hardcore Allflame").isCurrent()).isFalse();
        assertThat(findByExternalId(leagues, "Ruthless Allflame").isCurrent()).isFalse();
    }

    @Test
    void normalize_marksExactlyOneLeagueAsCurrent() {
        List<League> leagues = gateway.normalize(fixture());

        assertThat(leagues).filteredOn(League::isCurrent).hasSize(1);
    }

    @Test
    void normalize_defersExchangeActivityToLaterIngestionCrossCheck() {
        List<League> leagues = gateway.normalize(fixture());

        assertThat(leagues).allMatch(league -> !league.hasExchangeActivity());
    }

    private League findByExternalId(List<League> leagues, String externalId) {
        return leagues.stream()
                .filter(league -> league.externalId().equals(externalId))
                .findFirst()
                .orElseThrow();
    }

    private String fixture() {
        try {
            Path path = Path.of("src/test/resources/fixtures/leagues-response.json");
            return Files.readString(path);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
