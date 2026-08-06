package com.poeflipfinder.backend.entity;

/**
 * A divination card's turn-in reward, manually captured and classified per
 * docs/DATA_SOURCES.md. isPredictable = false for gamble/random-reward cards
 * excluded from Feature C (see docs/PRD.md § 7.3) -- kept, not omitted, so
 * the exclusion decision stays visible.
 */
public record DivinationCardReward(
        Currency card,
        int stackSize,
        Currency rewardCurrency,
        int rewardQuantity,
        boolean isPredictable) {
}
