package com.poeflipfinder.backend.presenter;

import com.poeflipfinder.backend.entity.CurrencyAmount;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesOutputBoundary;
import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesResponseModel;
import java.util.List;

public class ComputeFlipOpportunitiesPresenter implements ComputeFlipOpportunitiesOutputBoundary {

    private List<FlipOpportunityViewModel> viewModel = List.of();

    @Override
    public void present(ComputeFlipOpportunitiesResponseModel response) {
        viewModel = response.opportunities().stream().map(this::toViewModel).toList();
    }

    public List<FlipOpportunityViewModel> viewModel() {
        return viewModel;
    }

    private FlipOpportunityViewModel toViewModel(FlipOpportunity opportunity) {
        return new FlipOpportunityViewModel(
                opportunity.technique().name(),
                toViewModels(opportunity.start()),
                toViewModels(opportunity.via()),
                toViewModels(opportunity.sell()),
                opportunity.marginPercent(),
                toViewModel(opportunity.profit()),
                opportunity.volume(),
                opportunity.detail());
    }

    private List<CurrencyAmountViewModel> toViewModels(List<CurrencyAmount> amounts) {
        return amounts.stream().map(this::toViewModel).toList();
    }

    private CurrencyAmountViewModel toViewModel(CurrencyAmount amount) {
        return new CurrencyAmountViewModel(
                amount.currency().externalId(),
                amount.currency().displayName(),
                amount.currency().iconUrl(),
                amount.currency().itemType().name(),
                amount.quantity());
    }
}
