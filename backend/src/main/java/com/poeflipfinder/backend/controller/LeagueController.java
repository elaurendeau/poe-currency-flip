package com.poeflipfinder.backend.controller;

import com.poeflipfinder.backend.usecase.resolveleaguelist.ResolveLeagueListInputBoundary;

/**
 * One per inbound entry point (docs/CODE_STYLE.md § Clean Architecture).
 * No input to parse for this operation, so this simply invokes the boundary.
 */
public class LeagueController {

    private final ResolveLeagueListInputBoundary inputBoundary;

    public LeagueController(ResolveLeagueListInputBoundary inputBoundary) {
        this.inputBoundary = inputBoundary;
    }

    public void resolveLeagueList() {
        inputBoundary.resolveLeagueList();
    }
}
