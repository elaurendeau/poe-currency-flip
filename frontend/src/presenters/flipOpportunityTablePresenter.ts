import type { CurrencyAmount, FlipOpportunity, Technique } from '../entities/FlipOpportunity';

export type SortColumn = 'margin' | 'profit' | 'volume';
export type SortDirection = 'asc' | 'desc';
export type ThresholdValues = Partial<Record<SortColumn, number>>;

const COLUMN_VALUE: Record<SortColumn, (opportunity: FlipOpportunity) => number> = {
  margin: (opportunity) => opportunity.marginPercent,
  profit: (opportunity) => opportunity.profit,
  volume: (opportunity) => opportunity.volume,
};

// Identifies the trade route (technique + currencies), not the computed
// instance -- per PRD.md § 7.10, favorites must survive a refresh even
// though margin/profit/volume are recomputed fresh every time.
export function getRouteKey(opportunity: FlipOpportunity): string {
  const ids = (amounts: CurrencyAmount[]) => amounts.map((amount) => amount.currencyId).join('+');
  return [opportunity.technique, ids(opportunity.start), ids(opportunity.via), ids(opportunity.sell)].join('|');
}

export function filterByTechnique(
  opportunities: FlipOpportunity[],
  enabledTechniques: Record<Technique, boolean>,
): FlipOpportunity[] {
  return opportunities.filter((opportunity) => enabledTechniques[opportunity.technique]);
}

export function filterByThresholds(opportunities: FlipOpportunity[], thresholds: ThresholdValues): FlipOpportunity[] {
  const columns = Object.keys(thresholds) as SortColumn[];
  return opportunities.filter((opportunity) =>
    columns.every((column) => {
      const minimum = thresholds[column];
      return minimum === undefined || COLUMN_VALUE[column](opportunity) >= minimum;
    }),
  );
}

export function sortOpportunities(
  opportunities: FlipOpportunity[],
  column: SortColumn,
  direction: SortDirection,
): FlipOpportunity[] {
  const sorted = [...opportunities].sort((a, b) => COLUMN_VALUE[column](a) - COLUMN_VALUE[column](b));
  return direction === 'desc' ? sorted.reverse() : sorted;
}

export interface DisplayGroups {
  favorites: FlipOpportunity[];
  others: FlipOpportunity[];
}

export function partitionFavorites(opportunities: FlipOpportunity[], favoriteRouteKeys: Set<string>): DisplayGroups {
  const favorites: FlipOpportunity[] = [];
  const others: FlipOpportunity[] = [];
  for (const opportunity of opportunities) {
    (favoriteRouteKeys.has(getRouteKey(opportunity)) ? favorites : others).push(opportunity);
  }
  return { favorites, others };
}

export interface DisplayOptions {
  enabledTechniques: Record<Technique, boolean>;
  thresholds: ThresholdValues;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  favoriteRouteKeys: Set<string>;
}

// A favorite that no longer passes the technique/threshold filters simply
// disappears from both groups -- no placeholder, per PRD.md § 7.10.
export function buildDisplayGroups(opportunities: FlipOpportunity[], options: DisplayOptions): DisplayGroups {
  const filtered = filterByThresholds(filterByTechnique(opportunities, options.enabledTechniques), options.thresholds);
  const sorted = sortOpportunities(filtered, options.sortColumn, options.sortDirection);
  return partitionFavorites(sorted, options.favoriteRouteKeys);
}
