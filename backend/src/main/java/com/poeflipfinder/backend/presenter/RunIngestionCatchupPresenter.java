package com.poeflipfinder.backend.presenter;

import com.poeflipfinder.backend.usecase.runingestioncatchup.RunIngestionCatchupOutputBoundary;
import com.poeflipfinder.backend.usecase.runingestioncatchup.RunIngestionCatchupResponseModel;

/**
 * Shapes the interactor's result into a ViewModel. Formatting/shaping
 * decisions live here, not in the interactor (docs/CODE_STYLE.md § Clean
 * Architecture).
 */
public class RunIngestionCatchupPresenter implements RunIngestionCatchupOutputBoundary {

    private IngestionRefreshViewModel viewModel;

    @Override
    public void present(RunIngestionCatchupResponseModel response) {
        viewModel = new IngestionRefreshViewModel(
                response.hoursProcessed(),
                response.fullyCaughtUp(),
                response.lastProcessedChangeId(),
                response.skippedUnresolvableMarketEntryCount());
    }

    public IngestionRefreshViewModel viewModel() {
        return viewModel;
    }
}
