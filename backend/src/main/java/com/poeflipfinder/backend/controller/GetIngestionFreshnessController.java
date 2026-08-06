package com.poeflipfinder.backend.controller;

import com.poeflipfinder.backend.usecase.getingestionfreshness.GetIngestionFreshnessInputBoundary;
import com.poeflipfinder.backend.usecase.getingestionfreshness.IngestionFreshnessResponseModel;

/**
 * One per inbound entry point (docs/CODE_STYLE.md § Clean Architecture).
 * A simple read with no request model to build.
 */
public class GetIngestionFreshnessController {

    private final GetIngestionFreshnessInputBoundary inputBoundary;

    public GetIngestionFreshnessController(GetIngestionFreshnessInputBoundary inputBoundary) {
        this.inputBoundary = inputBoundary;
    }

    public IngestionFreshnessResponseModel getIngestionFreshness() {
        return inputBoundary.getIngestionFreshness();
    }
}
