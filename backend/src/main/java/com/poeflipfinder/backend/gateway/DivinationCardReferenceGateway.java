package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.DivinationCardReward;
import java.util.List;

/**
 * Defined by the use-case ring: the manually-captured divination card reward
 * data described in docs/DATA_SOURCES.md § Divination Card Turn-In Rewards.
 * Includes both predictable and non-predictable (gamble/non-currency) cards
 * -- see {@link DivinationCardReward}'s own docstring for why the exclusion
 * decision stays visible rather than simply omitting those entries.
 */
public interface DivinationCardReferenceGateway {

    List<DivinationCardReward> findAll();
}
