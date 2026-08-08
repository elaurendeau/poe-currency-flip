package com.poeflipfinder.backend.usecase.computeflipopportunities;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.CurrencyAmount;
import com.poeflipfinder.backend.entity.DivinationCardReward;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.Technique;
import com.poeflipfinder.backend.entity.UndercutQuote;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Computes Feature C (Divination Card Flip Finder, docs/PRD.md § 7.3)
 * opportunities: buy a full stack of a predictable-reward card via the
 * Exchange, turn it in, and resell the fixed reward for Chaos.
 *
 * <p>Matches cards and reward currencies against active snapshots by
 * {@link Currency#displayName()} rather than externalId -- the reference
 * data (docs/DATA_SOURCES.md § Divination Card Turn-In Rewards) has no
 * reliable source for GGG's internal item paths, only human-readable names
 * captured from the PoE Wiki.
 *
 * <p>The buy leg is priced competitively ({@link UndercutQuote#suggestedBuyPrice()},
 * same convention as every other technique's entry leg), preferring a Chaos
 * market and falling back to Divine. The resale leg is priced at
 * {@link UndercutQuote#marketSellPrice()} -- <strong>never</strong> the
 * round-trip-favorable {@code suggestedSellPrice()} -- since this is a
 * one-directional sell into existing demand, not a round-trip order, exactly
 * the same reasoning {@link BulkBuyOpportunityFinder} already applies to its
 * own exit leg.
 */
class DivinationCardOpportunityFinder {

    List<FlipOpportunity> find(
            List<ExchangeMarketSnapshot> snapshots, List<DivinationCardReward> cardRewards, DivineChaosRate rate) {
        if (rate == null) {
            return List.of();
        }

        List<FlipOpportunity> opportunities = new ArrayList<>();
        for (DivinationCardReward reward : cardRewards) {
            if (!reward.isPredictable()) {
                continue;
            }
            addIfPresent(opportunities, toOpportunity(reward, snapshots, rate));
        }
        return opportunities;
    }

    private FlipOpportunity toOpportunity(
            DivinationCardReward reward, List<ExchangeMarketSnapshot> snapshots, DivineChaosRate rate) {
        BuyLeg buyLeg = resolveBuyLeg(reward.card().displayName(), snapshots, rate);
        if (buyLeg == null) {
            return null;
        }

        double stackSize = reward.stackSize();
        double costInBase = stackSize / buyLeg.quote().suggestedBuyPrice().get();
        double costChaos =
                buyLeg.baseCurrency().equals(rate.chaosCurrency()) ? costInBase : costInBase * rate.chaosPerDivine();

        ResaleResult resale = resaleValueInChaos(reward.rewardCurrency(), reward.rewardQuantity(), snapshots, rate);
        if (resale == null) {
            return null;
        }

        double profitChaos = resale.chaosAmount() - costChaos;
        double marginPercent = profitChaos / costChaos * 100;
        String detail = "≈%sc per card".formatted(formatRatio(costChaos / stackSize));

        return new FlipOpportunity(
                Technique.DIVINATION_CARD,
                List.of(new CurrencyAmount(buyLeg.baseCurrency(), costInBase)),
                List.of(
                        new CurrencyAmount(buyLeg.cardCurrency(), stackSize),
                        new CurrencyAmount(resale.rewardCurrency(), reward.rewardQuantity())),
                List.of(new CurrencyAmount(rate.chaosCurrency(), resale.chaosAmount())),
                marginPercent,
                new CurrencyAmount(rate.chaosCurrency(), profitChaos),
                buyLeg.quote().buyLegStock(),
                detail);
    }

    /** Prefers a Chaos-side market for the card; falls back to Divine. Null means neither exists. */
    private BuyLeg resolveBuyLeg(String cardName, List<ExchangeMarketSnapshot> snapshots, DivineChaosRate rate) {
        BuyLeg chaosLeg = findLeg(cardName, snapshots, BaseCurrencyIds.CHAOS_EXTERNAL_ID, rate.chaosCurrency());
        if (chaosLeg != null) {
            return chaosLeg;
        }
        return findLeg(cardName, snapshots, BaseCurrencyIds.DIVINE_EXTERNAL_ID, rate.divineCurrency());
    }

    private BuyLeg findLeg(
            String otherName, List<ExchangeMarketSnapshot> snapshots, String baseExternalId, Currency baseCurrency) {
        for (ExchangeMarketSnapshot snapshot : snapshots) {
            Currency other = otherCurrency(snapshot, baseExternalId);
            if (other == null || !otherName.equals(other.displayName())) {
                continue;
            }
            Optional<UndercutQuote> quote = quoteAgainstBase(snapshot, baseExternalId);
            if (quote.isEmpty() || quote.get().suggestedBuyPrice().isEmpty()) {
                return null;
            }
            return new BuyLeg(baseCurrency, other, quote.get());
        }
        return null;
    }

    /**
     * Converts the card's fixed reward into Chaos. Chaos rewards need no
     * conversion; Divine rewards use the same averaged reference rate Bulk
     * Buy and Exchange Spread already rely on for cross-currency profit
     * normalization; any other reward currency needs its own market against
     * Chaos, priced at {@code marketSellPrice()} per this class's docstring.
     * Null means the reward currency can't be priced -- drop the opportunity.
     */
    private ResaleResult resaleValueInChaos(
            Currency rewardCurrency, int rewardQuantity, List<ExchangeMarketSnapshot> snapshots, DivineChaosRate rate) {
        String rewardName = rewardCurrency.displayName();
        if (rewardName.equals(rate.chaosCurrency().displayName())) {
            return new ResaleResult(rate.chaosCurrency(), rewardQuantity);
        }
        if (rewardName.equals(rate.divineCurrency().displayName())) {
            return new ResaleResult(rate.divineCurrency(), rewardQuantity * rate.chaosPerDivine());
        }
        return resaleThroughChaosMarket(rewardName, rewardQuantity, snapshots);
    }

    private ResaleResult resaleThroughChaosMarket(String rewardName, int rewardQuantity, List<ExchangeMarketSnapshot> snapshots) {
        for (ExchangeMarketSnapshot snapshot : snapshots) {
            Currency other = otherCurrency(snapshot, BaseCurrencyIds.CHAOS_EXTERNAL_ID);
            if (other == null || !rewardName.equals(other.displayName())) {
                continue;
            }
            Optional<UndercutQuote> quote = quoteAgainstBase(snapshot, BaseCurrencyIds.CHAOS_EXTERNAL_ID);
            if (quote.isEmpty() || quote.get().marketSellPrice() <= 0) {
                return null;
            }
            return new ResaleResult(other, rewardQuantity / quote.get().marketSellPrice());
        }
        return null;
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

    private Optional<UndercutQuote> quoteAgainstBase(ExchangeMarketSnapshot snapshot, String baseExternalId) {
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

    private void addIfPresent(List<FlipOpportunity> opportunities, FlipOpportunity opportunity) {
        if (opportunity != null) {
            opportunities.add(opportunity);
        }
    }

    private String formatRatio(double value) {
        if (value == Math.floor(value) && Double.isFinite(value)) {
            return String.valueOf((long) value);
        }
        return "%.2f".formatted(value);
    }

    private record BuyLeg(Currency baseCurrency, Currency cardCurrency, UndercutQuote quote) {
    }

    private record ResaleResult(Currency rewardCurrency, double chaosAmount) {
    }
}
