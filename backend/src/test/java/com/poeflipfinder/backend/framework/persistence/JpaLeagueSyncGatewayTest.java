package com.poeflipfinder.backend.framework.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.entity.League;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

@DataJpaTest
@TestPropertySource(properties = {"spring.flyway.enabled=false", "spring.jpa.hibernate.ddl-auto=create-drop"})
class JpaLeagueSyncGatewayTest {

    @Autowired
    private LeagueJpaRepository leagueJpaRepository;

    private JpaLeagueSyncGateway gateway;

    @AfterEach
    void cleanUp() {
        leagueJpaRepository.deleteAll();
    }

    @Test
    void upsertFromGgg_newLeague_isCreatedWithHasExchangeActivityFalse() {
        gateway = new JpaLeagueSyncGateway(leagueJpaRepository);

        List<League> result = gateway.upsertFromGgg(
                List.of(new League(null, "Allflame", "Allflame", true, false)));

        assertThat(result).hasSize(1);
        assertThat(result.get(0).externalId()).isEqualTo("Allflame");
        assertThat(result.get(0).displayName()).isEqualTo("Allflame");
        assertThat(result.get(0).isCurrent()).isTrue();
        assertThat(result.get(0).hasExchangeActivity()).isFalse();
    }

    @Test
    void upsertFromGgg_existingLeagueFromIngestion_updatesDisplayNameAndCurrentButPreservesHasExchangeActivity() {
        // Simulates a league row already created by ingestion (best-guess
        // displayName equal to externalId, hasExchangeActivity=true, isCurrent
        // never set) -- the GGG sync must enrich name/current without
        // clobbering the exchange-activity flag it doesn't know about.
        leagueJpaRepository.save(new LeagueJpaEntity("Allflame", "Allflame", false, true));
        gateway = new JpaLeagueSyncGateway(leagueJpaRepository);

        List<League> result = gateway.upsertFromGgg(
                List.of(new League(null, "Allflame", "Allflame", true, false)));

        assertThat(result).hasSize(1);
        League league = result.get(0);
        assertThat(league.isCurrent()).isTrue(); // updated from GGG
        assertThat(league.hasExchangeActivity()).isTrue(); // preserved from ingestion
        assertThat(leagueJpaRepository.findAll()).hasSize(1); // no duplicate row
    }

    @Test
    void upsertFromGgg_previouslyCurrentLeagueNoLongerCurrent_isUpdatedToFalse() {
        leagueJpaRepository.save(new LeagueJpaEntity("Standard", "Standard", true, false));
        gateway = new JpaLeagueSyncGateway(leagueJpaRepository);

        gateway.upsertFromGgg(List.of(new League(null, "Standard", "Standard", false, false)));

        Optional<LeagueJpaEntity> updated = leagueJpaRepository.findByExternalId("Standard");
        assertThat(updated).isPresent();
        assertThat(updated.get().isCurrent()).isFalse();
    }

    @Test
    void upsertFromGgg_multipleLeagues_allPersisted() {
        gateway = new JpaLeagueSyncGateway(leagueJpaRepository);

        List<League> result = gateway.upsertFromGgg(List.of(
                new League(null, "Standard", "Standard", false, false),
                new League(null, "Allflame", "Allflame", true, false)));

        assertThat(result).hasSize(2);
        assertThat(leagueJpaRepository.findAll()).hasSize(2);
    }

    @Test
    void upsertFromGgg_marksTheRowKnownToGgg_evenIfIngestionCreatedItFirst() {
        // A row ingestion already created (knownToGgg defaults false) must
        // become visible to GET /leagues once a real GGG sync confirms it.
        leagueJpaRepository.save(new LeagueJpaEntity("Standard", "Standard", false, true));
        gateway = new JpaLeagueSyncGateway(leagueJpaRepository);

        gateway.upsertFromGgg(List.of(new League(null, "Standard", "Standard", false, false)));

        Optional<LeagueJpaEntity> updated = leagueJpaRepository.findByExternalId("Standard");
        assertThat(updated).isPresent();
        assertThat(updated.get().isKnownToGgg()).isTrue();
    }
}
