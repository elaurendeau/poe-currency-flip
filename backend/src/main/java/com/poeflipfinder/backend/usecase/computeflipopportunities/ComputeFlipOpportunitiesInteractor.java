package com.poeflipfinder.backend.usecase.computeflipopportunities;

import com.poeflipfinder.backend.entity.CurrencyAmount;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.Technique;
import com.poeflipfinder.backend.gateway.SnapshotQueryGateway;
import java.util.List;
import java.util.Objects;

/**
 * Computes Feature B (Exchange Spread/Margin Finder, docs/PRD.md § 7.2)
 * opportunities. Named for the aggregate per docs/CODE_STYLE.md's own
 * worked example -- expected to grow a dependency per technique (Vendor
 * Recipe, Divination Card, Bulk Buy) as those features are built, merging
 * their computed opportunities into the same response list. Feature-B-only
 * for now.
 */
public class ComputeFlipOpportunitiesInteractor implements ComputeFlipOpportunitiesInputBoundary {

    private final SnapshotQueryGateway snapshotQueryGateway;
    private final ComputeFlipOpportunitiesOutputBoundary outputBoundary;

    public ComputeFlipOpportunitiesInteractor(
            SnapshotQueryGateway snapshotQueryGateway, ComputeFlipOpportunitiesOutputBoundary outputBoundary) {
        this.snapshotQueryGateway = snapshotQueryGateway;
        this.outputBoundary = outputBoundary;
    }

    @Override
    public void computeFlipOpportunities(ComputeFlipOpportunitiesRequestModel request) {
        List<ExchangeMarketSnapshot> snapshots = snapshotQueryGateway.findActiveSnapshots(request.leagueExternalId());
        List<FlipOpportunity> opportunities =
                snapshots.stream().map(this::toExchangeSpreadOpportunity).filter(Objects::nonNull).toList();
        outputBoundary.present(new ComputeFlipOpportunitiesResponseModel(opportunities));
    }

    /**
     * docs/PRD.md § 7.2: for a currency pair, the hourly lowest_ratio/
     * highest_ratio range is used as a proxy for the instant-vs-competitive
     * spread (no live order book is exposed -- docs/DATA_SOURCES.md). The
     * two stored extremes are independent (ratioA, ratioB) observations, not
     * reciprocals of each other. Derived price of A->B at either extreme is
     * ratioB/ratioA; the more favorable of the two extremes is used to buy
     * (proxy for "competitive"), the less favorable to sell back (proxy for
     * "instant"). Formula validated by hand against
     * docs/mockups/flip-row-reference.html's own worked example -- see
     * ComputeFlipOpportunitiesInteractorTest.
     */
    private FlipOpportunity toExchangeSpreadOpportunity(ExchangeMarketSnapshot snapshot) {
        double priceAtLowest = snapshot.lowestRatioB() / snapshot.lowestRatioA();
        double priceAtHighest = snapshot.highestRatioB() / snapshot.highestRatioA();
        if (!Double.isFinite(priceAtLowest) || !Double.isFinite(priceAtHighest)) {
            return null;
        }

        boolean buyAtHighestExtreme = priceAtHighest >= priceAtLowest;
        double buyPrice = buyAtHighestExtreme ? priceAtHighest : priceAtLowest;
        double sellBackPrice = buyAtHighestExtreme ? priceAtLowest : priceAtHighest;

        double startAmount = 1.0;
        double viaAmount = startAmount * buyPrice;
        double sellAmount = viaAmount / sellBackPrice;
        double profit = sellAmount - startAmount;
        double marginPercent = profit / startAmount * 100;
        double volume = buyAtHighestExtreme ? snapshot.highestStockA() : snapshot.lowestStockA();
        String detail = "instant %s:1 · competitive %s:1"
                .formatted(formatRatio(sellBackPrice), formatRatio(buyPrice));

        return new FlipOpportunity(
                Technique.EXCHANGE_SPREAD,
                List.of(new CurrencyAmount(snapshot.currencyA(), startAmount)),
                List.of(new CurrencyAmount(snapshot.currencyB(), viaAmount)),
                List.of(new CurrencyAmount(snapshot.currencyA(), sellAmount)),
                marginPercent,
                profit,
                volume,
                detail);
    }

    private String formatRatio(double value) {
        if (value == Math.floor(value) && Double.isFinite(value)) {
            return String.valueOf((long) value);
        }
        return "%.2f".formatted(value);
    }
}
