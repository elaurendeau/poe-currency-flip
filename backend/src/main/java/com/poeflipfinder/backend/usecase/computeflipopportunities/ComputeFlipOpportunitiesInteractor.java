package com.poeflipfinder.backend.usecase.computeflipopportunities;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.CurrencyAmount;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.Technique;
import com.poeflipfinder.backend.gateway.SnapshotQueryGateway;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

/**
 * Computes Feature B (Exchange Spread/Margin Finder, docs/PRD.md § 7.2)
 * opportunities. Named for the aggregate per docs/CODE_STYLE.md's own
 * worked example -- expected to grow a dependency per technique (Vendor
 * Recipe, Divination Card, Bulk Buy) as those features are built, merging
 * their computed opportunities into the same response list. Feature-B-only
 * for now.
 */
public class ComputeFlipOpportunitiesInteractor implements ComputeFlipOpportunitiesInputBoundary {

    // GGG's own path-style item identifiers for the two currencies Exchange
    // Spread is always anchored on -- see docs/DATA_SOURCES.md § Item Icons
    // for where this externalId format comes from.
    private static final String CHAOS_EXTERNAL_ID = "Metadata/Items/Currency/CurrencyRerollRare";
    private static final String DIVINE_EXTERNAL_ID = "Metadata/Items/Currency/CurrencyModValues";

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
        DivineChaosRate divineChaosRate = resolveDivineChaosRate(snapshots).orElse(null);
        List<FlipOpportunity> opportunities = snapshots.stream()
                .map(snapshot -> toExchangeSpreadOpportunity(snapshot, divineChaosRate))
                .filter(Objects::nonNull)
                .toList();
        outputBoundary.present(new ComputeFlipOpportunitiesResponseModel(opportunities));
    }

    /**
     * docs/PRD.md § 7.2: Exchange Spread always starts/sells in Chaos or
     * Divine -- a pair where neither side is a base currency isn't a flip a
     * player can act on without already holding that specific altcoin, so
     * it's dropped entirely. When Chaos is one of the two sides it always
     * wins the anchor over Divine, since profit is always Chaos-denominated
     * and Chaos-anchored opportunities need no rate conversion for it.
     *
     * <p>The hourly lowest_ratio/highest_ratio range is used as a proxy for
     * the instant-vs-competitive spread (no live order book is exposed --
     * docs/DATA_SOURCES.md). The two stored extremes are independent
     * (ratioA, ratioB) observations, not reciprocals of each other. Derived
     * price of start->via at either extreme is ratioVia/ratioStart; the more
     * favorable of the two extremes is the reference buy rate, the less
     * favorable the reference sell-back rate.
     *
     * <p>Those raw historical rates aren't directly tradeable -- currency
     * can't be transacted in fractions, and posting a limit order at the
     * literal best-ever observed rate rarely gets filled. Per docs/PRD.md
     * § 7.2, both reference rates are floored to whole numbers and then
     * undercut by 1 unit in whichever direction makes the posted order more
     * attractive than the going rate to a counterparty (worse for us than
     * the raw reference, but realistically achievable): the buy price steps
     * down, the sell price steps up. If the buy side can't sustain a -1
     * undercut (the reference rate doesn't clear 1 whole unit -- e.g. buying
     * Divine Orb with a single Chaos Orb), the opportunity is dropped
     * rather than shown with a meaningless price. Formula validated by hand
     * -- see ComputeFlipOpportunitiesInteractorTest.
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

        double priceAtLowest = lowestRatioVia / lowestRatioStart;
        double priceAtHighest = highestRatioVia / highestRatioStart;
        if (!Double.isFinite(priceAtLowest) || !Double.isFinite(priceAtHighest)) {
            return null;
        }

        boolean buyAtHighestExtreme = priceAtHighest >= priceAtLowest;
        double rawBuyPrice = buyAtHighestExtreme ? priceAtHighest : priceAtLowest;
        double rawSellBackPrice = buyAtHighestExtreme ? priceAtLowest : priceAtHighest;

        double suggestedBuyPrice = Math.floor(rawBuyPrice) - 1;
        if (suggestedBuyPrice < 1) {
            return null;
        }
        double suggestedSellPrice = Math.floor(rawSellBackPrice) + 1;

        double startAmount = 1.0;
        double viaAmount = startAmount * suggestedBuyPrice;
        double sellAmount = viaAmount / suggestedSellPrice;
        double rawProfit = sellAmount - startAmount;
        double marginPercent = rawProfit / startAmount * 100;
        double volume = buyAtHighestExtreme ? highestStockStart : lowestStockStart;
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
        boolean aIsChaos = CHAOS_EXTERNAL_ID.equals(currencyA.externalId());
        boolean bIsChaos = CHAOS_EXTERNAL_ID.equals(currencyB.externalId());
        boolean aIsBase = aIsChaos || DIVINE_EXTERNAL_ID.equals(currencyA.externalId());
        boolean bIsBase = bIsChaos || DIVINE_EXTERNAL_ID.equals(currencyB.externalId());
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
    private CurrencyAmount resolveProfitInChaos(Currency startCurrency, double rawProfit, DivineChaosRate divineChaosRate) {
        if (CHAOS_EXTERNAL_ID.equals(startCurrency.externalId())) {
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
            boolean aIsChaos = CHAOS_EXTERNAL_ID.equals(snapshot.currencyA().externalId());
            boolean bIsChaos = CHAOS_EXTERNAL_ID.equals(snapshot.currencyB().externalId());
            boolean aIsDivine = DIVINE_EXTERNAL_ID.equals(snapshot.currencyA().externalId());
            boolean bIsDivine = DIVINE_EXTERNAL_ID.equals(snapshot.currencyB().externalId());
            if (aIsChaos && bIsDivine) {
                return Optional.of(averagedRate(
                        snapshot.currencyA(),
                        snapshot.lowestRatioA(), snapshot.lowestRatioB(),
                        snapshot.highestRatioA(), snapshot.highestRatioB()));
            }
            if (bIsChaos && aIsDivine) {
                return Optional.of(averagedRate(
                        snapshot.currencyB(),
                        snapshot.lowestRatioB(), snapshot.lowestRatioA(),
                        snapshot.highestRatioB(), snapshot.highestRatioA()));
            }
        }
        return Optional.empty();
    }

    /**
     * Average of the hour's two rate extremes, expressed as Chaos received
     * per 1 Divine -- a simple point-estimate "fair value" for normalizing
     * profit figures, not a proposed trade (unlike buyPrice/sellBackPrice
     * above, which deliberately pick the more/less favorable extreme).
     */
    private DivineChaosRate averagedRate(
            Currency chaosCurrency,
            double lowestRatioChaos,
            double lowestRatioDivine,
            double highestRatioChaos,
            double highestRatioDivine) {
        double priceAtLowest = lowestRatioChaos / lowestRatioDivine;
        double priceAtHighest = highestRatioChaos / highestRatioDivine;
        return new DivineChaosRate(chaosCurrency, (priceAtLowest + priceAtHighest) / 2.0);
    }

    private record DivineChaosRate(Currency chaosCurrency, double chaosPerDivine) {}

    private String formatRatio(double value) {
        if (value == Math.floor(value) && Double.isFinite(value)) {
            return String.valueOf((long) value);
        }
        return "%.2f".formatted(value);
    }
}
