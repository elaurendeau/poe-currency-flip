package com.poeflipfinder.backend.entity;

/**
 * A tradeable item on the Currency Exchange: a currency orb or a divination card.
 * See docs/DATA_SOURCES.md § Item Icons for where externalId/iconUrl come from.
 */
public record Currency(
        Long id,
        String externalId,
        String displayName,
        String iconUrl,
        ItemType itemType) {

    public enum ItemType {
        CURRENCY,
        DIVINATION_CARD
    }
}
