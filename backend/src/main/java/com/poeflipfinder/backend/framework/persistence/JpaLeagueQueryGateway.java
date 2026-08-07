package com.poeflipfinder.backend.framework.persistence;

import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.LeagueQueryGateway;
import java.util.List;

/** The Frameworks & Drivers implementation of LeagueQueryGateway. */
public class JpaLeagueQueryGateway implements LeagueQueryGateway {

    private final LeagueJpaRepository leagueJpaRepository;

    public JpaLeagueQueryGateway(LeagueJpaRepository leagueJpaRepository) {
        this.leagueJpaRepository = leagueJpaRepository;
    }

    @Override
    public List<League> findAllLeagues() {
        // Only leagues an actual GGG Leagues API sync has confirmed exist --
        // never the private/one-off league names ingestion sees in raw trade
        // data (see LeagueJpaEntity.knownToGgg).
        return leagueJpaRepository.findByKnownToGggTrue().stream().map(this::toEntity).toList();
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
