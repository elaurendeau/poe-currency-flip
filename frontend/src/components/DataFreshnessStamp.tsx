import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';

interface DataFreshnessStampProps {
  freshness: IngestionFreshness | null;
  isLoading: boolean;
  error: Error | null;
  lastRefreshResult: IngestionRefreshResult | null;
}

// docs/PRD.md § 7.6: an absolute timestamp, not a vague relative time --
// full date, hour, minute, and millisecond. Format matches
// docs/mockups/flip-row-reference.html's .stamp exactly
// ("2026-08-05 14:32:07.418"): YYYY-MM-DD HH:MM:SS.mmm, 24-hour, local
// time -- not toLocaleString's locale-dependent "Aug 5, 2026, 2:32 PM"
// shape, which matches neither the mockup nor PRD's millisecond
// requirement.
export function formatFreshnessTimestamp(iso: string): string {
  const date = new Date(iso);
  const pad = (value: number, width = 2) => value.toString().padStart(width, '0');
  const datePart = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  const timePart = `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}.${pad(date.getMilliseconds(), 3)}`;
  return `${datePart} ${timePart}`;
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
