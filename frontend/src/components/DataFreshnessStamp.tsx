import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';
import { formatAbsoluteTimestamp } from '../presenters/timestampPresenter';

interface DataFreshnessStampProps {
  freshness: IngestionFreshness | null;
  isLoading: boolean;
  error: Error | null;
  lastRefreshResult: IngestionRefreshResult | null;
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
        <span className="stamp">{formatAbsoluteTimestamp(freshness.activeGenerationRefreshedAt)}</span>
      ) : (
        <span>Never refreshed</span>
      )}
      {partialCatchUpNotice}
    </div>
  );
}
