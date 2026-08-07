package com.poeflipfinder.backend.framework.web;

import com.poeflipfinder.backend.controller.ComputeFlipOpportunitiesController;
import com.poeflipfinder.backend.framework.web.generated.api.FlipOpportunitiesApi;
import com.poeflipfinder.backend.framework.web.generated.model.CurrencyAmount;
import com.poeflipfinder.backend.framework.web.generated.model.FlipOpportunity;
import com.poeflipfinder.backend.gateway.SnapshotQueryGateway;
import com.poeflipfinder.backend.presenter.ComputeFlipOpportunitiesPresenter;
import com.poeflipfinder.backend.presenter.CurrencyAmountViewModel;
import com.poeflipfinder.backend.presenter.FlipOpportunityViewModel;
import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesInteractor;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * Implements the contracts/openapi.yaml-generated FlipOpportunitiesApi
 * interface. Wires Controller+Presenter+Interactor together per request,
 * same pattern as LeagueRestController -- the Presenter holds per-request
 * state, so it is built fresh here rather than injected as a singleton bean.
 */
@RestController
public class FlipOpportunityRestController implements FlipOpportunitiesApi {

    private final SnapshotQueryGateway snapshotQueryGateway;

    public FlipOpportunityRestController(SnapshotQueryGateway snapshotQueryGateway) {
        this.snapshotQueryGateway = snapshotQueryGateway;
    }

    @Override
    public ResponseEntity<List<FlipOpportunity>> getFlipOpportunities(String league) {
        ComputeFlipOpportunitiesPresenter presenter = new ComputeFlipOpportunitiesPresenter();
        ComputeFlipOpportunitiesInteractor interactor =
                new ComputeFlipOpportunitiesInteractor(snapshotQueryGateway, presenter);
        ComputeFlipOpportunitiesController controller = new ComputeFlipOpportunitiesController(interactor);

        controller.computeFlipOpportunities(league);

        List<FlipOpportunity> contractOpportunities =
                presenter.viewModel().stream().map(this::toContractModel).toList();
        return ResponseEntity.ok(contractOpportunities);
    }

    private FlipOpportunity toContractModel(FlipOpportunityViewModel viewModel) {
        return new FlipOpportunity(
                FlipOpportunity.TechniqueEnum.fromValue(viewModel.technique()),
                toContractModels(viewModel.start()),
                toContractModels(viewModel.via()),
                toContractModels(viewModel.sell()),
                viewModel.marginPercent(),
                toContractModel(viewModel.profit()),
                viewModel.volume(),
                viewModel.detail());
    }

    private List<CurrencyAmount> toContractModels(List<CurrencyAmountViewModel> viewModels) {
        return viewModels.stream().map(this::toContractModel).toList();
    }

    private CurrencyAmount toContractModel(CurrencyAmountViewModel viewModel) {
        CurrencyAmount contractModel = new CurrencyAmount(
                viewModel.currencyId(),
                viewModel.name(),
                CurrencyAmount.ItemTypeEnum.fromValue(viewModel.itemType()),
                viewModel.quantity());
        if (viewModel.iconUrl() != null) {
            contractModel.iconUrl(viewModel.iconUrl());
        }
        return contractModel;
    }
}
