package com.poeflipfinder.backend.controller;

import com.poeflipfinder.backend.usecase.runingestioncatchup.RunIngestionCatchupInputBoundary;

/**
 * One per inbound entry point (docs/CODE_STYLE.md § Clean Architecture).
 * No input to parse for this operation, so this simply invokes the boundary.
 */
public class RefreshExchangeIngestionController {

    private final RunIngestionCatchupInputBoundary inputBoundary;

    public RefreshExchangeIngestionController(RunIngestionCatchupInputBoundary inputBoundary) {
        this.inputBoundary = inputBoundary;
    }

    public void refreshExchangeIngestion() {
        inputBoundary.runIngestionCatchup();
    }
}
