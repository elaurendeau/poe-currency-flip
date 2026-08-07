package com.poeflipfinder.backend.usecase.computeflipopportunities;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.CurrencyAmount;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.Technique;
import com.poeflipfinder.backend.entity.UndercutQuote;
import com.poeflipfinder.backend.gateway.SnapshotQueryGateway;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.stream.Stream;

/**
 * Computes Feature B (Exchange Spread/Margin Finder, docs/PRD.md § 7.2) and
 * Feature E (Bulk Buy, docs/PRD.md § 7.5) opportunities, merging both into
 * one response list. Named for the aggregate per docs/CODE_STYLE.md's own
 * worked example -- expected to grow a dependency per technique (Vendor
 * Recipe, Divination Card) as those features are built.
 */
public class ComputeFlipOpportunitiesInteractor implements ComputeFlipOpportunitiesInputBoundary {

    private final SnapshotQueryGateway snapshotQueryGateway;
    private final ComputeFlipOpportunitiesOutputBoundary outputBoundary;
    private final BulkBuyOpportunityFinder bulkBuyOpportunityFinder = new BulkBuyOpportunityFinder();

    public ComputeFlipOpportunitiesInteractor(
            SnapshotQueryGateway snapshotQueryGateway, ComputeFlipOpportunitiesOutputBoundary outputBoundary) {
        this.snapshotQueryGateway = snapshotQueryGateway;
        this.outputBoundary = outputBoundary;
    }

    @Override
    public void computeFlipOpportunities(ComputeFlipOpportunitiesRequestModel request) {
        List<ExchangeMarketSnapshot> snapshots = snapshotQueryGateway.findActiveSnapshots(request.leagueExternalId());
        DivineChaosRate divineChaosRate = resolveDivineChaosRate(snapshots).orElse(null);

        List<FlipOpportunity> exchangeSpread = snapshots.stream()
                .map(snapshot -> toExchangeSpreadOpportunity(snapshot, divineChaosRate))
                .filter(Objects::nonNull)
                .toList();
        List<FlipOpportunity> bulkBuy = bulkBuyOpportunityFinder.find(snapshots, divineChaosRate);

        outputBoundary.present(new ComputeFlipOpportunitiesResponseModel(
                Stream.concat(exchangeSpread.stream(), bulkBuy.stream()).toList()));
    }

    /**
     * docs/PRD.md § 7.2: Exchange Spread always starts/sells in Chaos or
     * Divine -- a pair where neither side is a base currency isn't a flip a
     * player can act on without already holding that specific altcoin, so
     * it's dropped entirely. When Chaos is one of the two sides it always
     * wins the anchor over Divine, since profit is always Chaos-denominated
     * and Chaos-anchored opportunities need no rate conversion for it.
     *
     * <p>See {@link UndercutQuote} for the realistic buy/sell pricing
     * applied to the raw hourly lowest_ratio/highest_ratio extremes.
     */
    private FlipOpportunity toExchangeSpreadOpportunity(
            ExchangeMarketSnapshot snapshot, DivineChaosRate divineChaosRate) {
        Boolean anchorOnA = resolveAnchorOnA(snapshot.currencyA(), snapshot.currencyB());
        if (anchorOnA == null) {
            return null;
        }

        Currency startCurrency = anchorOnA ? snapshot.currencyA() : snapshot.currencyB();
        Currency viaCurrency = anchorOnA ? snapshot.currencyB() : snapshot.currencyA();
        double lowestRatioStart = anchorOnA ? snapshot.lowestRatioA() : snapshot.lowestRatioB();
        double lowestRatioVia = anchorOnA ? snapshot.lowestRatioB() : snapshot.lowestRatioA();
        double highestRatioStart = anchorOnA ? snapshot.highestRatioA() : snapshot.highestRatioB();
        double highestRatioVia = anchorOnA ? snapshot.highestRatioB() : snapshot.highestRatioA();
        long lowestStockStart = anchorOnA ? snapshot.lowestStockA() : snapshot.lowestStockB();
        long highestStockStart = anchorOnA ? snapshot.highestStockA() : snapshot.highestStockB();

        Optional<UndercutQuote> quote = UndercutQuote.resolve(
                lowestRatioStart, lowestRatioVia, highestRatioStart, highestRatioVia,
                lowestStockStart, highestStockStart);
        if (quote.isEmpty() || quote.get().suggestedBuyPrice().isEmpty()) {
            return null;
        }
        double suggestedBuyPrice = quote.get().suggestedBuyPrice().get();
        double suggestedSellPrice = quote.get().suggestedSellPrice();

        double startAmount = 1.0;
        double viaAmount = startAmount * suggestedBuyPrice;
        double sellAmount = viaAmount / suggestedSellPrice;
        double rawProfit = sellAmount - startAmount;
        double marginPercent = rawProfit / startAmount * 100;
        double volume = quote.get().buyLegStock();
        String detail =
                "buy %s:1 · sell %s:1".formatted(formatRatio(suggestedBuyPrice), formatRatio(suggestedSellPrice));

        CurrencyAmount profit = resolveProfitInChaos(startCurrency, rawProfit, divineChaosRate);
        if (profit == null) {
            return null;
        }

        return new FlipOpportunity(
                Technique.EXCHANGE_SPREAD,
                List.of(new CurrencyAmount(startCurrency, startAmount)),
                List.of(new CurrencyAmount(viaCurrency, viaAmount)),
                List.of(new CurrencyAmount(startCurrency, sellAmount)),
                marginPercent,
                profit,
                volume,
                detail);
    }

    /** Null return means "neither side is a base currency -- drop this pair." */
    private Boolean resolveAnchorOnA(Currency currencyA, Currency currencyB) {
        boolean aIsChaos = BaseCurrencyIds.CHAOS_EXTERNAL_ID.equals(currencyA.externalId());
        boolean bIsChaos = BaseCurrencyIds.CHAOS_EXTERNAL_ID.equals(currencyB.externalId());
        boolean aIsBase = aIsChaos || BaseCurrencyIds.DIVINE_EXTERNAL_ID.equals(currencyA.externalId());
        boolean bIsBase = bIsChaos || BaseCurrencyIds.DIVINE_EXTERNAL_ID.equals(currencyB.externalId());
        if (!aIsBase && !bIsBase) {
            return null;
        }
        if (aIsChaos) {
            return true;
        }
        if (bIsChaos) {
            return false;
        }
        return aIsBase; // neither side is Chaos, so whichever is Divine anchors
    }

    /** Null return means "this opportunity's profit can't be normalized to Chaos -- drop it." */
    private CurrencyAmount resolveProfitInChaos(
            Currency startCurrency, double rawProfit, DivineChaosRate divineChaosRate) {
        if (BaseCurrencyIds.CHAOS_EXTERNAL_ID.equals(startCurrency.externalId())) {
            return new CurrencyAmount(startCurrency, rawProfit);
        }
        // startCurrency must be Divine at this point -- the only other base currency.
        if (divineChaosRate == null) {
            return null;
        }
        return new CurrencyAmount(divineChaosRate.chaosCurrency(), rawProfit * divineChaosRate.chaosPerDivine());
    }

    private Optional<DivineChaosRate> resolveDivineChaosRate(List<ExchangeMarketSnapshot> snapshots) {
        for (ExchangeMarketSnapshot snapshot : snapshots) {
            boolean aIsChaos = BaseCurrencyIds.CHAOS_EXTERNAL_ID.equals(snapshot.currencyA().externalId());
            boolean bIsChaos = BaseCurrencyIds.CHAOS_EXTERNAL_ID.equals(snapshot.currencyB().externalId());
            boolean aIsDivine = BaseCurrencyIds.DIVINE_EXTERNAL_ID.equals(snapshot.currencyA().externalId());
            boolean bIsDivine = BaseCurrencyIds.DIVINE_EXTERNAL_ID.equals(snapshot.currencyB().externalId());
            if (aIsChaos && bIsDivine) {
                return Optional.of(averagedRate(
                        snapshot.currencyA(), snapshot.currencyB(),
                        snapshot.lowestRatioA(), snapshot.lowestRatioB(),
                        snapshot.highestRatioA(), snapshot.highestRatioB()));
            }
            if (bIsChaos && aIsDivine) {
                return Optional.of(averagedRate(
                        snapshot.currencyB(), snapshot.currencyA(),
                        snapshot.lowestRatioB(), snapshot.lowestRatioA(),
                        snapshot.highestRatioB(), snapshot.highestRatioA()));
            }
        }
        return Optional.empty();
    }

    /**
     * Average of the hour's two rate extremes, expressed as Chaos received
     * per 1 Divine -- a simple point-estimate "fair value" for normalizing
     * profit figures, not a proposed trade (unlike the buy/sell prices in
     * {@link UndercutQuote}, which deliberately pick the more/less favorable
     * extreme).
     */
    private DivineChaosRate averagedRate(
            Currency chaosCurrency,
            Currency divineCurrency,
            double lowestRatioChaos,
            double lowestRatioDivine,
            double highestRatioChaos,
            double highestRatioDivine) {
        double priceAtLowest = lowestRatioChaos / lowestRatioDivine;
        double priceAtHighest = highestRatioChaos / highestRatioDivine;
        return new DivineChaosRate(chaosCurrency, divineCurrency, (priceAtLowest + priceAtHighest) / 2.0);
    }

    private String formatRatio(double value) {
        if (value == Math.floor(value) && Double.isFinite(value)) {
            return String.valueOf((long) value);
        }
        return "%.2f".formatted(value);
    }
}
