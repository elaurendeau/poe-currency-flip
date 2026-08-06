package com.poeflipfinder.backend.framework.persistence;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CurrencyJpaRepository extends JpaRepository<CurrencyJpaEntity, Long> {

    Optional<CurrencyJpaEntity> findByExternalId(String externalId);
}
