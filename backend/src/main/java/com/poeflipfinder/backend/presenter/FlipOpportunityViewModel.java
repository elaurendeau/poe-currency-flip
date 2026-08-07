package com.poeflipfinder.backend.presenter;

import java.util.List;

public record FlipOpportunityViewModel(
        String technique,
        List<CurrencyAmountViewModel> start,
        List<CurrencyAmountViewModel> via,
        List<CurrencyAmountViewModel> sell,
        double marginPercent,
        CurrencyAmountViewModel profit,
        double volume,
        String detail) {
}
