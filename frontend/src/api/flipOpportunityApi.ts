import { API_BASE_URL } from '../config/env';
import type { CurrencyAmount, FlipOpportunity } from '../entities/FlipOpportunity';
import type { components } from './generated/schema';

type FlipOpportunityDto = components['schemas']['FlipOpportunity'];
type CurrencyAmountDto = components['schemas']['CurrencyAmount'];

export class FlipOpportunityApiError extends Error {}

function toCurrencyAmount(dto: CurrencyAmountDto): CurrencyAmount {
  return { currencyId: dto.currencyId, name: dto.name, iconUrl: dto.iconUrl ?? null, quantity: dto.quantity };
}

function toFlipOpportunity(dto: FlipOpportunityDto): FlipOpportunity {
  return {
    technique: dto.technique,
    start: dto.start.map(toCurrencyAmount),
    via: dto.via.map(toCurrencyAmount),
    sell: dto.sell.map(toCurrencyAmount),
    marginPercent: dto.marginPercent,
    profit: dto.profit,
    volume: dto.volume,
    detail: dto.detail,
  };
}

export async function fetchFlipOpportunities(leagueId: string): Promise<FlipOpportunity[]> {
  const response = await fetch(`${API_BASE_URL}/flip-opportunities?league=${encodeURIComponent(leagueId)}`);
  if (!response.ok) {
    throw new FlipOpportunityApiError(`GET /flip-opportunities failed with status ${response.status}`);
  }
  const dtos: FlipOpportunityDto[] = await response.json();
  return dtos.map(toFlipOpportunity);
}
