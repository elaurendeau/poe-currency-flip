package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.League;
import java.util.List;

/**
 * Defined by the use-case ring for whatever it needs from the outside world
 * (docs/CODE_STYLE.md § Clean Architecture). The interactor calls this
 * without knowing whether the implementation is the real GGG API or a test.
 */
public interface LeagueGateway {

    /**
     * Fetches the current league list, already filtered to exclude Solo
     * Self-Found leagues (no Currency Exchange access) per
     * docs/ARCHITECTURE.md § League Resolution steps 1-2.
     */
    List<League> fetchLeagues();
}
