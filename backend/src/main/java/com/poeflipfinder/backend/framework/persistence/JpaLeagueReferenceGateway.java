package com.poeflipfinder.backend.framework.persistence;

import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.LeagueReferenceGateway;
import org.springframework.transaction.annotation.Transactional;

/**
 * The Frameworks & Drivers implementation of LeagueReferenceGateway. On
 * create, best-guess-populates both externalId and displayName from the raw
 * league string in the exchange payload -- no richer metadata is available
 * at this seam. See docs/ARCHITECTURE.md's explicit follow-up: a later task
 * should let ResolveLeagueListInteractor enrich this via the live Leagues
 * API instead.
 */
public class JpaLeagueReferenceGateway implements LeagueReferenceGateway {

    private final LeagueJpaRepository leagueJpaRepository;

    public JpaLeagueReferenceGateway(LeagueJpaRepository leagueJpaRepository) {
        this.leagueJpaRepository = leagueJpaRepository;
    }

    @Override
    @Transactional
    public League resolveOrCreateLeague(String leagueExternalId) {
        LeagueJpaEntity jpaEntity = leagueJpaRepository
                .findByExternalId(leagueExternalId)
                .orElseGet(() -> new LeagueJpaEntity(leagueExternalId, leagueExternalId, false, false));

        jpaEntity.setHasExchangeActivity(true);
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
