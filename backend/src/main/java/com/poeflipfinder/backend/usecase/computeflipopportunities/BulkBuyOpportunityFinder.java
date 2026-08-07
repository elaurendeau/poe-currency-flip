package com.poeflipfinder.backend.usecase.computeflipopportunities;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.CurrencyAmount;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.Technique;
import com.poeflipfinder.backend.entity.UndercutQuote;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Computes Feature E (Bulk Buy / triangular arbitrage, docs/PRD.md § 7.5)
 * opportunities: for any currency X that trades against both Chaos and
 * Divine, checks whether buying X with one and reselling it for the other
 * beats the direct Chaos<->Divine exchange rate -- evaluated in both
 * directions independently, since undercut pricing isn't symmetric (one
 * direction can be viable while the reverse isn't).
 */
class BulkBuyOpportunityFinder {

    List<FlipOpportunity> find(List<ExchangeMarketSnapshot> snapshots, DivineChaosRate rate) {
        if (rate == null) {
            return List.of();
        }

        Map<Currency, ExchangeMarketSnapshot> chaosLegs =
                legsByOtherCurrency(snapshots, BaseCurrencyIds.CHAOS_EXTERNAL_ID);
        Map<Currency, ExchangeMarketSnapshot> divineLegs =
                legsByOtherCurrency(snapshots, BaseCurrencyIds.DIVINE_EXTERNAL_ID);

        List<FlipOpportunity> opportunities = new ArrayList<>();
        for (Map.Entry<Currency, ExchangeMarketSnapshot> entry : chaosLegs.entrySet()) {
            Currency intermediary = entry.getKey();
            ExchangeMarketSnapshot divineSnapshot = divineLegs.get(intermediary);
            if (divineSnapshot == null) {
                continue;
            }

            Optional<UndercutQuote> chaosQuote = quoteFor(entry.getValue(), BaseCurrencyIds.CHAOS_EXTERNAL_ID);
            Optional<UndercutQuote> divineQuote = quoteFor(divineSnapshot, BaseCurrencyIds.DIVINE_EXTERNAL_ID);
            if (chaosQuote.isEmpty() || divineQuote.isEmpty()) {
                continue;
            }

            addIfPresent(opportunities, chaosToDivine(intermediary, chaosQuote.get(), divineQuote.get(), rate));
            addIfPresent(opportunities, divineToChaos(intermediary, chaosQuote.get(), divineQuote.get(), rate));
        }
        return opportunities;
    }

    /**
     * All snapshots where one side is the given base currency, keyed by the
     * other ("intermediary") side -- excluding the base-to-base reference
     * pair itself (e.g. Chaos<->Divine), which isn't a valid intermediary.
     */
    private Map<Currency, ExchangeMarketSnapshot> legsByOtherCurrency(
            List<ExchangeMarketSnapshot> snapshots, String baseExternalId) {
        Map<Currency, ExchangeMarketSnapshot> legs = new HashMap<>();
        for (ExchangeMarketSnapshot snapshot : snapshots) {
            Currency other = otherCurrency(snapshot, baseExternalId);
            if (other == null || isBaseCurrency(other)) {
                continue;
            }
            legs.put(other, snapshot);
        }
        return legs;
    }

    private Currency otherCurrency(ExchangeMarketSnapshot snapshot, String baseExternalId) {
        if (baseExternalId.equals(snapshot.currencyA().externalId())) {
            return snapshot.currencyB();
        }
        if (baseExternalId.equals(snapshot.currencyB().externalId())) {
            return snapshot.currencyA();
        }
        return null;
    }

    private boolean isBaseCurrency(Currency currency) {
        return BaseCurrencyIds.CHAOS_EXTERNAL_ID.equals(currency.externalId())
                || BaseCurrencyIds.DIVINE_EXTERNAL_ID.equals(currency.externalId());
    }

    private Optional<UndercutQuote> quoteFor(ExchangeMarketSnapshot snapshot, String baseExternalId) {
        boolean baseIsA = baseExternalId.equals(snapshot.currencyA().externalId());
        double lowestRatioStart = baseIsA ? snapshot.lowestRatioA() : snapshot.lowestRatioB();
        double lowestRatioVia = baseIsA ? snapshot.lowestRatioB() : snapshot.lowestRatioA();
        double highestRatioStart = baseIsA ? snapshot.highestRatioA() : snapshot.highestRatioB();
        double highestRatioVia = baseIsA ? snapshot.highestRatioB() : snapshot.highestRatioA();
        long lowestStockStart = baseIsA ? snapshot.lowestStockA() : snapshot.lowestStockB();
        long highestStockStart = baseIsA ? snapshot.highestStockA() : snapshot.highestStockB();
        return UndercutQuote.resolve(
                lowestRatioStart, lowestRatioVia, highestRatioStart, highestRatioVia,
                lowestStockStart, highestStockStart);
    }

    /**
     * Buy the intermediary with Chaos, sell it for Divine, compare against
     * the direct Chaos->Divine baseline at the raw, non-undercut, averaged
     * rate -- a comparison reference, not an order we're suggesting the user
     * post.
     *
     * <p>Scaled so the trade always ends at exactly 1 Divine sold, rather
     * than starting from 1 Chaos: "1 Chaos -> 0.005 Divine" is a meaningless
     * fraction to read, since Chaos is the much smaller-value currency here.
     * "~230 Chaos -> 1 Divine" is how a player actually thinks about this
     * direction, and lines up directly with the "direct ~225 c/div" figure
     * in the detail line. Margin is scale-invariant (a ratio); profit scales
     * with the trade size, same as it would if a player actually multiplied
     * the trade up. Per-unit rates (buy/sell/direct) and volume (real market
     * depth, independent of how much of it we choose to reference) are
     * unaffected by the rescaling either way.
     */
    private FlipOpportunity chaosToDivine(
            Currency intermediary, UndercutQuote chaosLeg, UndercutQuote divineLeg, DivineChaosRate rate) {
        if (chaosLeg.suggestedBuyPrice().isEmpty()) {
            return null;
        }
        double sellAmount = 1.0;
        double viaAmount = divineLeg.suggestedSellPrice(); // sells for exactly 1 Divine, by definition
        double startAmount = viaAmount / chaosLeg.suggestedBuyPrice().get();

        double directBaselineDivine = startAmount / rate.chaosPerDivine();
        double marginPercent = (sellAmount - directBaselineDivine) / directBaselineDivine * 100;
        double profitChaos = (sellAmount - directBaselineDivine) * rate.chaosPerDivine();
        double volume = Math.min(chaosLeg.buyLegStock(), divineLeg.sellLegStock());
        String detail = detail(chaosLeg.suggestedBuyPrice().get(), divineLeg.suggestedSellPrice(), rate.chaosPerDivine());

        return new FlipOpportunity(
                Technique.BULK_BUY,
                List.of(new CurrencyAmount(rate.chaosCurrency(), startAmount)),
                List.of(new CurrencyAmount(intermediary, viaAmount)),
                List.of(new CurrencyAmount(rate.divineCurrency(), sellAmount)),
                marginPercent,
                new CurrencyAmount(rate.chaosCurrency(), profitChaos),
                volume,
                detail);
    }

    /**
     * Buy the intermediary with 1 Divine, sell it for Chaos, compare against
     * the direct Divine->Chaos baseline -- already Chaos-denominated, so the
     * profit figure needs no conversion.
     */
    private FlipOpportunity divineToChaos(
            Currency intermediary, UndercutQuote chaosLeg, UndercutQuote divineLeg, DivineChaosRate rate) {
        if (divineLeg.suggestedBuyPrice().isEmpty()) {
            return null;
        }
        double viaAmount = divineLeg.suggestedBuyPrice().get();
        double sellAmountChaos = viaAmount / chaosLeg.suggestedSellPrice();
        double directBaselineChaos = rate.chaosPerDivine();
        double marginPercent = (sellAmountChaos - directBaselineChaos) / directBaselineChaos * 100;
        double profitChaos = sellAmountChaos - directBaselineChaos;
        double volume = Math.min(divineLeg.buyLegStock(), chaosLeg.sellLegStock());
        String detail = detail(viaAmount, chaosLeg.suggestedSellPrice(), rate.chaosPerDivine());

        return new FlipOpportunity(
                Technique.BULK_BUY,
                List.of(new CurrencyAmount(rate.divineCurrency(), 1.0)),
                List.of(new CurrencyAmount(intermediary, viaAmount)),
                List.of(new CurrencyAmount(rate.chaosCurrency(), sellAmountChaos)),
                marginPercent,
                new CurrencyAmount(rate.chaosCurrency(), profitChaos),
                volume,
                detail);
    }

    private void addIfPresent(List<FlipOpportunity> opportunities, FlipOpportunity opportunity) {
        if (opportunity != null) {
            opportunities.add(opportunity);
        }
    }

    private String detail(double buyPrice, double sellPrice, double chaosPerDivine) {
        return "buy %s:1 · sell %s:1 · direct ~%s c/div"
                .formatted(formatRatio(buyPrice), formatRatio(sellPrice), formatRatio(chaosPerDivine));
    }

    private String formatRatio(double value) {
        if (value == Math.floor(value) && Double.isFinite(value)) {
            return String.valueOf((long) value);
        }
        return "%.2f".formatted(value);
    }
}
