export interface IngestionFreshness {
  lastProcessedChangeId: number | null;
  activeGenerationRefreshedAt: string | null;
}

export interface IngestionRefreshResult {
  hoursProcessed: number;
  fullyCaughtUp: boolean;
  lastProcessedChangeId: number | null;
  skippedUnresolvableMarketEntryCount: number;
}
