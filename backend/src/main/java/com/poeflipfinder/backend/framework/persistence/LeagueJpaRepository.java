package com.poeflipfinder.backend.framework.persistence;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface LeagueJpaRepository extends JpaRepository<LeagueJpaEntity, Long> {

    Optional<LeagueJpaEntity> findByExternalId(String externalId);
}
