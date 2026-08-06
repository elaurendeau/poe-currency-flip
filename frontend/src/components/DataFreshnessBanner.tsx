import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';

interface DataFreshnessBannerProps {
  freshness: IngestionFreshness | null;
  isLoading: boolean;
  error: Error | null;
  lastRefreshResult: IngestionRefreshResult | null;
}

// docs/PRD.md § 7.6: an absolute timestamp, not a vague relative time --
// full date, hour, minute, and second (millisecond precision is available
// from the server but not meaningful to a human reading the banner).
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

export function DataFreshnessBanner({
  freshness,
  isLoading,
  error,
  lastRefreshResult,
}: DataFreshnessBannerProps) {
  if (error) {
    return (
      <div className="freshness-banner freshness-banner--error">Failed to load market data freshness</div>
    );
  }

  if (isLoading) {
    return <div className="freshness-banner freshness-banner--loading">Loading market data freshness…</div>;
  }

  const partialCatchUpNotice =
    lastRefreshResult && !lastRefreshResult.fullyCaughtUp ? (
      <span className="freshness-banner__partial">
        {' '}
        — only partially caught up ({lastRefreshResult.hoursProcessed}h processed); click refresh again to
        continue.
      </span>
    ) : null;

  return (
    <div className="freshness-banner">
      {freshness?.activeGenerationRefreshedAt ? (
        <>
          Market data last refreshed: {formatFreshnessTimestamp(freshness.activeGenerationRefreshedAt)}
          {partialCatchUpNotice}
        </>
      ) : (
        <>Market data has never been refreshed{partialCatchUpNotice}</>
      )}
    </div>
  );
}
