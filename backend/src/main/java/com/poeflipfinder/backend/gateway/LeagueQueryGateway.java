package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.League;
import java.util.List;

/**
 * Read side of the league cache (docs/SCHEMA.md § League cache) --
 * deliberately separate from LeagueGateway (the live GGG fetch) and
 * LeagueSyncGateway (the write side), since each has a different caller and
 * lifecycle: this one backs the cheap GET /leagues read every page load
 * makes, so it must never itself call out to GGG.
 */
public interface LeagueQueryGateway {

    List<League> findAllLeagues();
}
