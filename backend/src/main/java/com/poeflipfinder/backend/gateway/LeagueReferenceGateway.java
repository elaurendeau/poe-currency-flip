package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.League;

/**
 * Defined by the use-case ring: resolve a league string from the Currency
 * Exchange payload to a persisted League row, creating one on first sight.
 * Unlike currency resolution this can't fail -- the league name arrives
 * directly in the payload, no external lookup needed. Marks
 * hasExchangeActivity, the real gate for League Resolution step 3
 * (docs/SCHEMA.md § League cache, docs/ARCHITECTURE.md § League Resolution).
 */
public interface LeagueReferenceGateway {

    League resolveOrCreateLeague(String leagueExternalId);
}
