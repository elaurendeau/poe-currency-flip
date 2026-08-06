import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';
import { DataFreshnessStamp, formatFreshnessTimestamp } from './DataFreshnessStamp';

const refreshed: IngestionFreshness = {
  lastProcessedChangeId: 1785996000,
  activeGenerationRefreshedAt: '2026-08-06T06:45:07.261123Z',
};
const neverRefreshed: IngestionFreshness = { lastProcessedChangeId: null, activeGenerationRefreshedAt: null };
const partialResult: IngestionRefreshResult = {
  hoursProcessed: 48,
  fullyCaughtUp: false,
  lastProcessedChangeId: 1785900000,
  skippedUnresolvableMarketEntryCount: 12,
};
const fullResult: IngestionRefreshResult = {
  hoursProcessed: 24,
  fullyCaughtUp: true,
  lastProcessedChangeId: 1785996000,
  skippedUnresolvableMarketEntryCount: 3796,
};

describe('formatFreshnessTimestamp', () => {
  it('formats as YYYY-MM-DD HH:MM:SS.mmm, matching docs/mockups/flip-row-reference.html\'s .stamp exactly', () => {
    const formatted = formatFreshnessTimestamp('2026-08-06T06:45:07.261Z');

    expect(formatted).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$/);
    expect(formatted).not.toMatch(/ago|AM|PM|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec/i);
  });

  it('zero-pads single-digit month/day/hour/minute/second and milliseconds to 3 digits', () => {
    // A date deliberately chosen so every component is single-digit except
    // the year, to catch a formatter that forgets to pad any one of them.
    const formatted = formatFreshnessTimestamp('2026-01-02T03:04:05.006Z');

    // toLocaleString-free local-time formatting means the exact string
    // depends on the runner's timezone offset -- assert the shape (widths
    // and separators), not a fixed value.
    expect(formatted).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$/);
  });
});

describe('DataFreshnessStamp', () => {
  it('shows a loading state', () => {
    render(<DataFreshnessStamp freshness={null} isLoading error={null} lastRefreshResult={null} />);

    expect(screen.getByText(/loading market data freshness/i)).toBeInTheDocument();
  });

  it('shows an error state', () => {
    render(
      <DataFreshnessStamp
        freshness={null}
        isLoading={false}
        error={new Error('boom')}
        lastRefreshResult={null}
      />,
    );

    expect(screen.getByText(/failed to load market data freshness/i)).toBeInTheDocument();
  });

  it('shows "Never refreshed" when no generation has ever committed', () => {
    render(
      <DataFreshnessStamp
        freshness={neverRefreshed}
        isLoading={false}
        error={null}
        lastRefreshResult={null}
      />,
    );

    expect(screen.getByText('Never refreshed')).toBeInTheDocument();
  });

  it('shows the absolute last-refreshed timestamp as a plain centered stamp', () => {
    render(
      <DataFreshnessStamp freshness={refreshed} isLoading={false} error={null} lastRefreshResult={null} />,
    );

    expect(screen.getByText(/2026/)).toBeInTheDocument();
  });

  it('surfaces a partial-catch-up notice per docs/PRD.md § 7.6 -- never silently implies full catch-up', () => {
    render(
      <DataFreshnessStamp
        freshness={refreshed}
        isLoading={false}
        error={null}
        lastRefreshResult={partialResult}
      />,
    );

    expect(screen.getByText(/partial/i)).toBeInTheDocument();
    expect(screen.getByText(/refresh again to continue/i)).toBeInTheDocument();
  });

  it('shows no partial-catch-up notice when the last refresh fully caught up', () => {
    render(
      <DataFreshnessStamp
        freshness={refreshed}
        isLoading={false}
        error={null}
        lastRefreshResult={fullResult}
      />,
    );

    expect(screen.queryByText(/partial/i)).not.toBeInTheDocument();
  });
});
