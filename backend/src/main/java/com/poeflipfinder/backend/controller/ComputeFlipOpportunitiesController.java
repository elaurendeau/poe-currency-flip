package com.poeflipfinder.backend.controller;

import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesInputBoundary;
import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesRequestModel;

public class ComputeFlipOpportunitiesController {

    private final ComputeFlipOpportunitiesInputBoundary inputBoundary;

    public ComputeFlipOpportunitiesController(ComputeFlipOpportunitiesInputBoundary inputBoundary) {
        this.inputBoundary = inputBoundary;
    }

    public void computeFlipOpportunities(String leagueExternalId) {
        inputBoundary.computeFlipOpportunities(new ComputeFlipOpportunitiesRequestModel(leagueExternalId));
    }
}
