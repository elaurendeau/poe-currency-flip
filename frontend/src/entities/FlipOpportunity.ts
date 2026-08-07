export type Technique = 'VENDOR_RECIPE' | 'EXCHANGE_SPREAD' | 'DIVINATION_CARD' | 'BULK_BUY';

export const ALL_TECHNIQUES: Technique[] = ['VENDOR_RECIPE', 'EXCHANGE_SPREAD', 'DIVINATION_CARD', 'BULK_BUY'];

export type ItemType = 'CURRENCY' | 'DIVINATION_CARD';

export interface CurrencyAmount {
  currencyId: string;
  name: string;
  iconUrl: string | null;
  itemType: ItemType;
  quantity: number;
}

export interface FlipOpportunity {
  technique: Technique;
  start: CurrencyAmount[];
  via: CurrencyAmount[];
  sell: CurrencyAmount[];
  marginPercent: number;
  profit: CurrencyAmount; // always denominated in Chaos Orb -- see TECH_STACK.md's row design
  volume: number;
  detail: string;
}
