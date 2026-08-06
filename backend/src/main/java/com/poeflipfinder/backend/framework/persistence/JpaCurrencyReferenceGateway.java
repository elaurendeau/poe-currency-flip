package com.poeflipfinder.backend.framework.persistence;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.gateway.CurrencyReferenceGateway;
import com.poeflipfinder.backend.gateway.ItemIconGateway;
import java.util.Optional;

/**
 * The Frameworks & Drivers implementation of CurrencyReferenceGateway.
 * Depends on the ItemIconGateway interface, not the concrete GGG class --
 * Dependency Inversion, and lets a test double stand in during testing.
 */
public class JpaCurrencyReferenceGateway implements CurrencyReferenceGateway {

    private final CurrencyJpaRepository currencyJpaRepository;
    private final ItemIconGateway itemIconGateway;

    public JpaCurrencyReferenceGateway(CurrencyJpaRepository currencyJpaRepository, ItemIconGateway itemIconGateway) {
        this.currencyJpaRepository = currencyJpaRepository;
        this.itemIconGateway = itemIconGateway;
    }

    @Override
    public Optional<Currency> resolveOrCreateCurrency(String externalId) {
        Optional<CurrencyJpaEntity> existing = currencyJpaRepository.findByExternalId(externalId);
        if (existing.isPresent()) {
            return Optional.of(toEntity(existing.get()));
        }

        return itemIconGateway.lookupItem(externalId).map(this::createFrom);
    }

    private Currency createFrom(Currency resolved) {
        CurrencyJpaEntity saved = currencyJpaRepository.save(new CurrencyJpaEntity(
                resolved.externalId(), resolved.displayName(), resolved.iconUrl(), resolved.itemType()));
        return toEntity(saved);
    }

    private Currency toEntity(CurrencyJpaEntity jpaEntity) {
        return new Currency(
                jpaEntity.getId(),
                jpaEntity.getExternalId(),
                jpaEntity.getDisplayName(),
                jpaEntity.getIconUrl(),
                jpaEntity.getItemType());
    }
}
