import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';

interface DataFreshnessStampProps {
  freshness: IngestionFreshness | null;
  isLoading: boolean;
  error: Error | null;
  lastRefreshResult: IngestionRefreshResult | null;
}

// docs/PRD.md § 7.6: an absolute timestamp, not a vague relative time --
// full date, hour, minute, and second (millisecond precision is available
// from the server but not meaningful to a human reading this).
export function formatFreshnessTimestamp(iso: string): string {
  const date = new Date(iso);
  return date.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

// Centered in the header, per docs/mockups/flip-row-reference.html's
// .topbar-center -- a plain timestamp, not a full-width banner strip.
export function DataFreshnessStamp({
  freshness,
  isLoading,
  error,
  lastRefreshResult,
}: DataFreshnessStampProps) {
  if (error) {
    return <div className="header-center header-center--error">Failed to load market data freshness</div>;
  }

  if (isLoading) {
    return <div className="header-center">Loading market data freshness…</div>;
  }

  const partialCatchUpNotice =
    lastRefreshResult && !lastRefreshResult.fullyCaughtUp ? (
      <span className="header-center__partial">
        {' '}
        — partial ({lastRefreshResult.hoursProcessed}h), refresh again to continue
      </span>
    ) : null;

  return (
    <div className="header-center">
      {freshness?.activeGenerationRefreshedAt ? (
        <span className="stamp">{formatFreshnessTimestamp(freshness.activeGenerationRefreshedAt)}</span>
      ) : (
        <span>Never refreshed</span>
      )}
      {partialCatchUpNotice}
    </div>
  );
}
