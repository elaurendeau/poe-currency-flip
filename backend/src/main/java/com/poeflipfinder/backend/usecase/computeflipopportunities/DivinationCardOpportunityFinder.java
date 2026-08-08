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
 * <p>Both the buy leg (which base currency the card itself trades against)
 * and the resale leg (which base currency the reward trades against) prefer
 * a Chaos market and fall back to Divine independently -- the two legs are
 * unrelated trades and one's base doesn't constrain the other's. The buy leg
 * is priced competitively ({@link UndercutQuote#suggestedBuyPrice()}, same
 * convention as every other technique's entry leg). The resale leg is priced
 * at {@link UndercutQuote#marketSellPrice()} -- <strong>never</strong> the
 * round-trip-favorable {@code suggestedSellPrice()} -- since this is a
 * one-directional sell into existing demand, not a round-trip order, exactly
 * the same reasoning {@link BulkBuyOpportunityFinder} already applies to its
 * own exit leg.
 *
 * <p><strong>Both legs also re-orient if the "other" side turns out to be
 * worth more than 1 base unit.</strong> Quoting "card units per 1 Chaos"
 * floors to 0 for a card worth, say, 200 Chaos, and the -1 competitive
 * undercut then pushes it negative -- {@code suggestedBuyPrice()}/{@code
 * marketSellPrice()} come back unusable and the whole opportunity was
 * silently dropped, even for a card genuinely trading with real volume (a
 * real production incident: The Sephirot, ~200c/card, confirmed via raw GGG
 * data to have real volume and stock that this class nonetheless discarded).
 * When that happens, both legs retry with the *other* currency as the base
 * instead ("Chaos per 1 card" / "Chaos per 1 reward unit" -- a sane,
 * floorable number), scaling by multiplication instead of division. This is
 * the same underlying idea {@link BulkBuyOpportunityFinder} already uses
 * (scale to end at exactly 1 of the expensive currency, not start at exactly
 * 1 of the cheap one) but applied as a genuine auto-detected fallback rather
 * than a hardcoded direction, since a card's value relative to Chaos/Divine
 * isn't known ahead of time the way Bulk Buy's fixed Chaos/Divine pair is.
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
        double costInBase = buyLeg.priceIsPerCard()
                ? stackSize * buyLeg.quote().suggestedBuyPrice().get()
                : stackSize / buyLeg.quote().suggestedBuyPrice().get();
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
            return resolveOrientedBuyQuote(snapshot, baseExternalId, baseCurrency, other);
        }
        return null;
    }

    /** See this class's docstring for why both orientations are tried. Null means neither is viable. */
    private BuyLeg resolveOrientedBuyQuote(
            ExchangeMarketSnapshot snapshot, String baseExternalId, Currency baseCurrency, Currency card) {
        Optional<UndercutQuote> asBase = quoteAgainstBase(snapshot, baseExternalId);
        if (asBase.isPresent() && asBase.get().suggestedBuyPrice().isPresent()) {
            return new BuyLeg(baseCurrency, card, asBase.get(), false);
        }
        Optional<UndercutQuote> asCard = quoteAgainstBase(snapshot, card.externalId());
        if (asCard.isPresent() && asCard.get().suggestedBuyPrice().isPresent()) {
            return new BuyLeg(baseCurrency, card, asCard.get(), true);
        }
        return null;
    }

    /**
     * Converts the card's fixed reward into Chaos. Chaos rewards need no
     * conversion; Divine rewards use the same averaged reference rate Bulk
     * Buy and Exchange Spread already rely on for cross-currency profit
     * normalization; any other reward currency needs its own market against
     * Chaos or Divine, priced at {@code marketSellPrice()} per this class's
     * docstring -- Chaos is tried first, Divine is a fallback (some
     * currencies, especially higher-value ones, trade mainly against Divine
     * rather than Chaos; without this fallback a card whose reward only has
     * a live Divine market was silently dropped even though its buy leg
     * resolved fine via the same Divine fallback the buy leg already has).
     * Null means the reward currency can't be priced against either base --
     * drop the opportunity.
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
        ResaleResult viaChaos = resaleThroughMarket(
                rewardName, rewardQuantity, snapshots, BaseCurrencyIds.CHAOS_EXTERNAL_ID, 1.0);
        if (viaChaos != null) {
            return viaChaos;
        }
        return resaleThroughMarket(
                rewardName, rewardQuantity, snapshots, BaseCurrencyIds.DIVINE_EXTERNAL_ID, rate.chaosPerDivine());
    }

    /**
     * {@code chaosPerBaseUnit} converts the base currency's own market-rate
     * proceeds into Chaos -- 1.0 when the base already is Chaos, {@code
     * rate.chaosPerDivine()} when the base is Divine.
     */
    private ResaleResult resaleThroughMarket(
            String rewardName, int rewardQuantity, List<ExchangeMarketSnapshot> snapshots,
            String baseExternalId, double chaosPerBaseUnit) {
        for (ExchangeMarketSnapshot snapshot : snapshots) {
            Currency other = otherCurrency(snapshot, baseExternalId);
            if (other == null || !rewardName.equals(other.displayName())) {
                continue;
            }
            return resolveOrientedResaleQuote(snapshot, baseExternalId, other, rewardQuantity, chaosPerBaseUnit);
        }
        return null;
    }

    /** See this class's docstring for why both orientations are tried. Null means neither is viable. */
    private ResaleResult resolveOrientedResaleQuote(
            ExchangeMarketSnapshot snapshot, String baseExternalId, Currency reward,
            int rewardQuantity, double chaosPerBaseUnit) {
        Optional<UndercutQuote> asBase = quoteAgainstBase(snapshot, baseExternalId);
        if (asBase.isPresent() && asBase.get().marketSellPrice() > 0) {
            double baseAmount = rewardQuantity / asBase.get().marketSellPrice();
            return new ResaleResult(reward, baseAmount * chaosPerBaseUnit);
        }
        Optional<UndercutQuote> asReward = quoteAgainstBase(snapshot, reward.externalId());
        if (asReward.isPresent() && asReward.get().marketSellPrice() > 0) {
            double baseAmount = rewardQuantity * asReward.get().marketSellPrice();
            return new ResaleResult(reward, baseAmount * chaosPerBaseUnit);
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

    /** {@code priceIsPerCard}: true means {@code quote} is "base units per 1 card" (multiply); false means "card units per 1 base unit" (divide). */
    private record BuyLeg(Currency baseCurrency, Currency cardCurrency, UndercutQuote quote, boolean priceIsPerCard) {
    }

    private record ResaleResult(Currency rewardCurrency, double chaosAmount) {
    }
}
