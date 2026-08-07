package com.poeflipfinder.backend.framework.persistence;

import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.LeagueSyncGateway;
import java.util.List;
import org.springframework.transaction.annotation.Transactional;

/** The Frameworks & Drivers implementation of LeagueSyncGateway. */
public class JpaLeagueSyncGateway implements LeagueSyncGateway {

    private final LeagueJpaRepository leagueJpaRepository;

    public JpaLeagueSyncGateway(LeagueJpaRepository leagueJpaRepository) {
        this.leagueJpaRepository = leagueJpaRepository;
    }

    @Override
    @Transactional
    public List<League> upsertFromGgg(List<League> leagues) {
        return leagues.stream().map(this::upsert).toList();
    }

    private League upsert(League league) {
        LeagueJpaEntity jpaEntity = leagueJpaRepository
                .findByExternalId(league.externalId())
                .orElseGet(() -> new LeagueJpaEntity(league.externalId(), league.displayName(), false, false));

        jpaEntity.setDisplayName(league.displayName());
        jpaEntity.setCurrent(league.isCurrent());
        jpaEntity.setKnownToGgg(true);
        // hasExchangeActivity is deliberately untouched -- only ingestion knows that.

        LeagueJpaEntity saved = leagueJpaRepository.save(jpaEntity);
        return toEntity(saved);
    }

    private League toEntity(LeagueJpaEntity jpaEntity) {
        return new League(
                jpaEntity.getId(),
                jpaEntity.getExternalId(),
                jpaEntity.getDisplayName(),
                jpaEntity.isCurrent(),
                jpaEntity.hasExchangeActivity());
    }
}
