package com.poeflipfinder.backend.controller;

import com.poeflipfinder.backend.usecase.refreshleaguelist.RefreshLeagueListInputBoundary;

/**
 * One per inbound entry point (docs/CODE_STYLE.md § Clean Architecture).
 * No input to parse for this operation, so this simply invokes the boundary.
 */
public class RefreshLeagueListController {

    private final RefreshLeagueListInputBoundary inputBoundary;

    public RefreshLeagueListController(RefreshLeagueListInputBoundary inputBoundary) {
        this.inputBoundary = inputBoundary;
    }

    public void refreshLeagueList() {
        inputBoundary.refreshLeagueList();
    }
}
