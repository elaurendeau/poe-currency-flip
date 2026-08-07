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
 * <p>{@code marketSellPrice} is a second, less aggressive sell reference:
 * the same less-favorable hourly extreme, floored, but without the +1
 * push. It represents dumping into already-observed demand at a rate at
 * least as good as the worst real fill seen this hour, rather than posting
 * a fresh limit order and hoping it fills -- used where a caller (Bulk Buy)
 * judges a second unfilled limit order too risky on top of the buy leg's.
 */
public record UndercutQuote(
        Optional<Double> suggestedBuyPrice,
        double suggestedSellPrice,
        double marketSellPrice,
        double buyLegStock,
        double sellLegStock) {

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
        double rawSellBackPrice = buyAtHighestExtreme ? priceAtLowest : priceAtHighest;

        double flooredBuyPrice = Math.floor(rawBuyPrice) - 1;
        Optional<Double> suggestedBuyPrice = flooredBuyPrice >= 1 ? Optional.of(flooredBuyPrice) : Optional.empty();
        double flooredSellBackPrice = Math.floor(rawSellBackPrice);
        double suggestedSellPrice = flooredSellBackPrice + 1;
        double marketSellPrice = flooredSellBackPrice;
        double buyLegStock = buyAtHighestExtreme ? highestStockStart : lowestStockStart;
        double sellLegStock = buyAtHighestExtreme ? lowestStockStart : highestStockStart;

        return Optional.of(new UndercutQuote(
                suggestedBuyPrice, suggestedSellPrice, marketSellPrice, buyLegStock, sellLegStock));
    }
}
