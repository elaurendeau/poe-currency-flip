package com.poeflipfinder.backend.entity;

import java.util.List;

/**
 * A computed flip result, matching the Start/Via/Sell/Margin/Profit/Volume
 * row structure in docs/TECH_STACK.md § UI Style. Never persisted -- see
 * docs/SCHEMA.md § Deliberately not a table: computed fresh on every refresh.
 */
public record FlipOpportunity(
        Technique technique,
        List<CurrencyAmount> start,
        List<CurrencyAmount> via,
        List<CurrencyAmount> sell,
        double marginPercent,
        CurrencyAmount profit, // always denominated in Chaos Orb, per TECH_STACK.md's row design -- never the start currency's own unit
        double volume,
        String detail) {
}
