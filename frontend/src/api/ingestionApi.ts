import { API_BASE_URL } from '../config/env';
import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';
import type { components } from './generated/schema';

type IngestionFreshnessDto = components['schemas']['IngestionFreshness'];
type IngestionRefreshResultDto = components['schemas']['IngestionRefreshResult'];

export class IngestionApiError extends Error {}

function toIngestionFreshness(dto: IngestionFreshnessDto): IngestionFreshness {
  return {
    lastProcessedChangeId: dto.lastProcessedChangeId ?? null,
    activeGenerationRefreshedAt: dto.activeGenerationRefreshedAt ?? null,
  };
}

function toIngestionRefreshResult(dto: IngestionRefreshResultDto): IngestionRefreshResult {
  return {
    hoursProcessed: dto.hoursProcessed,
    fullyCaughtUp: dto.fullyCaughtUp,
    lastProcessedChangeId: dto.lastProcessedChangeId ?? null,
    skippedUnresolvableMarketEntryCount: dto.skippedUnresolvableMarketEntryCount,
  };
}

export async function fetchIngestionFreshness(): Promise<IngestionFreshness> {
  const response = await fetch(`${API_BASE_URL}/exchange-ingestion/freshness`);
  if (!response.ok) {
    throw new IngestionApiError(`GET /exchange-ingestion/freshness failed with status ${response.status}`);
  }
  const dto: IngestionFreshnessDto = await response.json();
  return toIngestionFreshness(dto);
}

export async function refreshIngestion(): Promise<IngestionRefreshResult> {
  const response = await fetch(`${API_BASE_URL}/exchange-ingestion/refresh`, { method: 'POST' });
  if (!response.ok) {
    throw new IngestionApiError(`POST /exchange-ingestion/refresh failed with status ${response.status}`);
  }
  const dto: IngestionRefreshResultDto = await response.json();
  return toIngestionRefreshResult(dto);
}
