package com.poeflipfinder.backend.entity;

/**
 * A league cached from GGG's public Leagues API. See docs/ARCHITECTURE.md
 * § League Resolution for how hasExchangeActivity is determined.
 */
public record League(
        Long id,
        String externalId,
        String displayName,
        boolean isCurrent,
        boolean hasExchangeActivity) {
}
