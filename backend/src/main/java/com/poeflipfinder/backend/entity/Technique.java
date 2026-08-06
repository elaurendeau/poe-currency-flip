package com.poeflipfinder.backend.entity;

/**
 * Which flip-finding mechanism produced a FlipOpportunity. Maps to
 * docs/PRD.md features: 7.1 vendor recipe, 7.2 exchange spread,
 * 7.3 divination card, 7.5 Bulk Buy (triangular arbitrage).
 */
public enum Technique {
    VENDOR_RECIPE,
    EXCHANGE_SPREAD,
    DIVINATION_CARD,
    BULK_BUY
}
