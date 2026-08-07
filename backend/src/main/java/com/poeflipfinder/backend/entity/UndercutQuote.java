package com.poeflipfinder.backend.entity;

import java.util.Optional;

/**
 * The realistic, postable buy/sell prices for a currency pair leg, derived
 * from the hour's two observed rate extremes (docs/PRD.md § 7.2). Currency
 * can't be transacted in fractions, and posting a limit order at the literal
 * best-ever observed rate rarely gets filled, so both reference rates are
 * floored to whole numbers and then undercut by 1 unit in whichever
 * direction makes the posted order more attractive than the going rate to a
 * counterparty: the buy price steps down, the sell price steps up.
 *
 * <p>{@code suggestedBuyPrice} is an {@link Optional} because the -1
 * undercut can push a small reference rate (e.g. buying Divine Orb with a
 * single Chaos Orb) below 1, at which point there's no meaningful buy order
 * to suggest. {@code suggestedSellPrice} has no such failure mode -- it's
 * always computable once the input ratios are finite, regardless of whether
 * this same leg's buy price is viable. This asymmetry matters: a caller
 * evaluating a trade that only needs this leg's *sell* price (not its buy
 * price) must still get a usable quote even when the buy side is empty.
 *
 * <p>{@code marketSellPrice} is a second, less aggressive sell reference for
 * a genuine one-directional sell of the "via" currency into the base
 * currency (used by Bulk Buy, which is dumping a currency it already holds,
 * not round-tripping the same pair). It must <strong>not</strong> be
 * confused with {@code suggestedSellPrice}'s hourly extreme: that extreme is
 * chosen to be favorable for a same-pair round trip (buy this pair's cheap
 * extreme, sell back at its dear extreme -- the whole premise of the
 * Exchange Spread feature), which makes it the <em>optimistic</em> case for
 * a one-directional seller, not the conservative one. {@code
 * marketSellPrice} instead reuses the hour's <em>other</em> real extreme --
 * the same one {@code suggestedBuyPrice} is undercut from -- floored with no
 * further push, representing the worst of the two real fills seen this hour
 * from a seller's perspective: fewer base-currency units back per unit of
 * "via" currency sold than the round-trip-favorable extreme would imply.
 */
public record UndercutQuote(
        Optional<Double> suggestedBuyPrice,
        double suggestedSellPrice,
        double marketSellPrice,
        double buyLegStock) {

    public static Optional<UndercutQuote> resolve(
            double lowestRatioStart,
            double lowestRatioVia,
            double highestRatioStart,
            double highestRatioVia,
            double lowestStockStart,
            double highestStockStart) {
        double priceAtLowest = lowestRatioVia / lowestRatioStart;
        double priceAtHighest = highestRatioVia / highestRatioStart;
        if (!Double.isFinite(priceAtLowest) || !Double.isFinite(priceAtHighest)) {
            return Optional.empty();
        }

        boolean buyAtHighestExtreme = priceAtHighest >= priceAtLowest;
        double rawBuyPrice = buyAtHighestExtreme ? priceAtHighest : priceAtLowest;
        double rawRoundTripSellPrice = buyAtHighestExtreme ? priceAtLowest : priceAtHighest;

        double flooredBuyPrice = Math.floor(rawBuyPrice) - 1;
        Optional<Double> suggestedBuyPrice = flooredBuyPrice >= 1 ? Optional.of(flooredBuyPrice) : Optional.empty();
        double suggestedSellPrice = Math.floor(rawRoundTripSellPrice) + 1;
        double marketSellPrice = Math.floor(rawBuyPrice);
        double buyLegStock = buyAtHighestExtreme ? highestStockStart : lowestStockStart;

        return Optional.of(new UndercutQuote(suggestedBuyPrice, suggestedSellPrice, marketSellPrice, buyLegStock));
    }
}
