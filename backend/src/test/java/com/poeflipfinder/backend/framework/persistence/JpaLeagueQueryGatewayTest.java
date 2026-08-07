package com.poeflipfinder.backend.framework.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;

import com.poeflipfinder.backend.entity.League;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

/**
 * Exercises the DB-cached league read against H2, mirroring
 * JpaSnapshotQueryGatewayTest's approach -- V1__init_schema.sql's SQL isn't
 * portable to H2 as-is.
 */
@DataJpaTest
@TestPropertySource(properties = {"spring.flyway.enabled=false", "spring.jpa.hibernate.ddl-auto=create-drop"})
class JpaLeagueQueryGatewayTest {

    @Autowired
    private LeagueJpaRepository leagueJpaRepository;

    private JpaLeagueQueryGateway gateway;

    @AfterEach
    void cleanUp() {
        leagueJpaRepository.deleteAll();
    }

    @Test
    void findAllLeagues_returnsEveryKnownToGggLeagueWithFullFields() {
        gateway = new JpaLeagueQueryGateway(leagueJpaRepository);
        leagueJpaRepository.save(knownLeague("Standard", "Standard", false, false));
        leagueJpaRepository.save(knownLeague("Allflame", "Allflame", true, true));

        List<League> leagues = gateway.findAllLeagues();

        assertThat(leagues)
                .extracting(League::externalId, League::displayName, League::isCurrent, League::hasExchangeActivity)
                .containsExactlyInAnyOrder(
                        tuple("Standard", "Standard", false, false),
                        tuple("Allflame", "Allflame", true, true));
    }

    @Test
    void findAllLeagues_excludesLeaguesNotKnownToGgg() {
        // A one-off private league name ingestion saw in raw trade data --
        // never confirmed by an actual GGG Leagues API sync (LeagueJpaEntity
        // defaults knownToGgg to false), so it must never reach the dropdown.
        gateway = new JpaLeagueQueryGateway(leagueJpaRepository);
        leagueJpaRepository.save(new LeagueJpaEntity("Some Private League (PL12345)", "Some Private League (PL12345)", false, true));
        leagueJpaRepository.save(knownLeague("Standard", "Standard", false, true));

        List<League> leagues = gateway.findAllLeagues();

        assertThat(leagues).extracting(League::externalId).containsExactly("Standard");
    }

    @Test
    void findAllLeagues_noLeaguesCachedYet_returnsEmptyList() {
        gateway = new JpaLeagueQueryGateway(leagueJpaRepository);

        assertThat(gateway.findAllLeagues()).isEmpty();
    }

    private LeagueJpaEntity knownLeague(
            String externalId, String displayName, boolean isCurrent, boolean hasExchangeActivity) {
        LeagueJpaEntity entity = new LeagueJpaEntity(externalId, displayName, isCurrent, hasExchangeActivity);
        entity.setKnownToGgg(true);
        return entity;
    }
}
