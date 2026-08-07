import { describe, expect, it } from 'vitest';
import type { CurrencyAmount, FlipOpportunity, Technique } from '../entities/FlipOpportunity';
import {
  buildDisplayGroups,
  filterByTechnique,
  filterByThresholds,
  getRouteKey,
  partitionFavorites,
  sortOpportunities,
} from './flipOpportunityTablePresenter';

function currencyAmount(currencyId: string, name: string, quantity: number): CurrencyAmount {
  return { currencyId, name, iconUrl: null, itemType: 'CURRENCY', quantity };
}

function chaosProfit(quantity: number): CurrencyAmount {
  return currencyAmount('chaos', 'Chaos Orb', quantity);
}

function opportunity(overrides: Partial<FlipOpportunity> = {}): FlipOpportunity {
  return {
    technique: 'EXCHANGE_SPREAD',
    start: [currencyAmount('chaos', 'Chaos Orb', 1)],
    via: [currencyAmount('wisdom', 'Scroll of Wisdom', 366)],
    sell: [currencyAmount('chaos', 'Chaos Orb', 1.9784)],
    marginPercent: 97.84,
    profit: chaosProfit(0.9784),
    volume: 1234,
    detail: 'instant 185:1 · competitive 366:1',
    ...overrides,
  };
}

const allEnabled: Record<Technique, boolean> = {
  VENDOR_RECIPE: true,
  EXCHANGE_SPREAD: true,
  DIVINATION_CARD: true,
  BULK_BUY: true,
};

describe('getRouteKey', () => {
  it('is identical for two opportunities with the same technique and currencies', () => {
    const a = opportunity();
    const b = opportunity({ marginPercent: 12, profit: chaosProfit(0.1), volume: 5 });

    expect(getRouteKey(a)).toBe(getRouteKey(b));
  });

  it('differs when the technique differs', () => {
    const a = opportunity({ technique: 'EXCHANGE_SPREAD' });
    const b = opportunity({ technique: 'BULK_BUY' });

    expect(getRouteKey(a)).not.toBe(getRouteKey(b));
  });

  it('differs when the via currency differs', () => {
    const a = opportunity();
    const b = opportunity({
      via: [currencyAmount('portal', 'Portal Scroll', 10)],
    });

    expect(getRouteKey(a)).not.toBe(getRouteKey(b));
  });
});

describe('filterByTechnique', () => {
  it('keeps only opportunities whose technique is enabled', () => {
    const spread = opportunity({ technique: 'EXCHANGE_SPREAD' });
    const bulk = opportunity({ technique: 'BULK_BUY' });

    const result = filterByTechnique([spread, bulk], { ...allEnabled, BULK_BUY: false });

    expect(result).toEqual([spread]);
  });
});

describe('filterByThresholds', () => {
  it('keeps opportunities at or above every provided threshold', () => {
    const low = opportunity({ marginPercent: 10, volume: 5 });
    const high = opportunity({ marginPercent: 90, volume: 500 });

    expect(filterByThresholds([low, high], { margin: 50 })).toEqual([high]);
    expect(filterByThresholds([low, high], { volume: 5 })).toEqual([low, high]);
  });

  it('applies multiple thresholds together', () => {
    const meetsMarginOnly = opportunity({ marginPercent: 90, volume: 1 });
    const meetsBoth = opportunity({ marginPercent: 90, volume: 100 });

    const result = filterByThresholds([meetsMarginOnly, meetsBoth], { margin: 50, volume: 50 });

    expect(result).toEqual([meetsBoth]);
  });

  it('returns everything when no thresholds are provided', () => {
    const items = [opportunity(), opportunity({ marginPercent: 1 })];

    expect(filterByThresholds(items, {})).toEqual(items);
  });
});

describe('sortOpportunities', () => {
  it('sorts ascending by the requested column', () => {
    const low = opportunity({ profit: chaosProfit(1) });
    const high = opportunity({ profit: chaosProfit(9) });

    expect(sortOpportunities([high, low], 'profit', 'asc')).toEqual([low, high]);
  });

  it('sorts descending by the requested column', () => {
    const low = opportunity({ volume: 1 });
    const high = opportunity({ volume: 9 });

    expect(sortOpportunities([low, high], 'volume', 'desc')).toEqual([high, low]);
  });

  it('does not mutate the input array', () => {
    const items = [opportunity({ marginPercent: 1 }), opportunity({ marginPercent: 9 })];
    const original = [...items];

    sortOpportunities(items, 'margin', 'desc');

    expect(items).toEqual(original);
  });
});

describe('partitionFavorites', () => {
  it('splits opportunities into favorites and others by route key', () => {
    const favorited = opportunity({ technique: 'EXCHANGE_SPREAD' });
    const notFavorited = opportunity({ technique: 'BULK_BUY' });

    const result = partitionFavorites([favorited, notFavorited], new Set([getRouteKey(favorited)]));

    expect(result).toEqual({ favorites: [favorited], others: [notFavorited] });
  });

  it('preserves relative order within each group', () => {
    const favA = opportunity({ technique: 'EXCHANGE_SPREAD', volume: 1 });
    const favB = opportunity({
      technique: 'EXCHANGE_SPREAD',
      volume: 2,
      via: [currencyAmount('x', 'X', 1)],
    });
    const keys = new Set([getRouteKey(favA), getRouteKey(favB)]);

    const result = partitionFavorites([favA, favB], keys);

    expect(result.favorites).toEqual([favA, favB]);
  });
});

describe('buildDisplayGroups', () => {
  it('filters by technique and threshold, sorts, then partitions favorites -- a filtered-out favorite disappears entirely', () => {
    const keptFavorite = opportunity({ technique: 'EXCHANGE_SPREAD', marginPercent: 90, volume: 1 });
    const filteredOutFavorite = opportunity({
      technique: 'BULK_BUY',
      marginPercent: 5,
      volume: 1,
      via: [currencyAmount('y', 'Y', 1)],
    });
    const nonFavorite = opportunity({
      technique: 'EXCHANGE_SPREAD',
      marginPercent: 50,
      volume: 2,
      via: [currencyAmount('z', 'Z', 1)],
    });

    const result = buildDisplayGroups([keptFavorite, filteredOutFavorite, nonFavorite], {
      enabledTechniques: { ...allEnabled, BULK_BUY: false },
      thresholds: {},
      sortColumn: 'margin',
      sortDirection: 'desc',
      favoriteRouteKeys: new Set([getRouteKey(keptFavorite), getRouteKey(filteredOutFavorite)]),
    });

    expect(result.favorites).toEqual([keptFavorite]);
    expect(result.others).toEqual([nonFavorite]);
  });
});
