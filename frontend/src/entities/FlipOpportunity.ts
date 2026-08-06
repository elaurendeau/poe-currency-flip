export type Technique = 'VENDOR_RECIPE' | 'EXCHANGE_SPREAD' | 'DIVINATION_CARD' | 'BULK_BUY';

export const ALL_TECHNIQUES: Technique[] = ['VENDOR_RECIPE', 'EXCHANGE_SPREAD', 'DIVINATION_CARD', 'BULK_BUY'];

export interface CurrencyAmount {
  currencyId: string;
  name: string;
  iconUrl: string | null;
  quantity: number;
}

export interface FlipOpportunity {
  technique: Technique;
  start: CurrencyAmount[];
  via: CurrencyAmount[];
  sell: CurrencyAmount[];
  marginPercent: number;
  profit: number;
  volume: number;
  detail: string;
}
