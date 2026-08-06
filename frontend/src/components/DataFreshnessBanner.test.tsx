import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';
import { DataFreshnessBanner, formatFreshnessTimestamp } from './DataFreshnessBanner';

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
  it('formats an ISO timestamp as an absolute date/time, not a relative time', () => {
    const formatted = formatFreshnessTimestamp('2026-08-06T06:45:07.261123Z');

    expect(formatted).not.toMatch(/ago|minute|hour(?!:)/i);
    expect(formatted).toMatch(/2026/);
  });
});

describe('DataFreshnessBanner', () => {
  it('shows a loading state', () => {
    render(<DataFreshnessBanner freshness={null} isLoading error={null} lastRefreshResult={null} />);

    expect(screen.getByText(/loading market data freshness/i)).toBeInTheDocument();
  });

  it('shows an error state', () => {
    render(
      <DataFreshnessBanner
        freshness={null}
        isLoading={false}
        error={new Error('boom')}
        lastRefreshResult={null}
      />,
    );

    expect(screen.getByText(/failed to load market data freshness/i)).toBeInTheDocument();
  });

  it('shows "never refreshed" when no generation has ever committed', () => {
    render(
      <DataFreshnessBanner
        freshness={neverRefreshed}
        isLoading={false}
        error={null}
        lastRefreshResult={null}
      />,
    );

    expect(screen.getByText(/never been refreshed/i)).toBeInTheDocument();
  });

  it('shows the absolute last-refreshed timestamp', () => {
    render(
      <DataFreshnessBanner freshness={refreshed} isLoading={false} error={null} lastRefreshResult={null} />,
    );

    expect(screen.getByText(/market data last refreshed:/i)).toBeInTheDocument();
    expect(screen.getByText(/2026/)).toBeInTheDocument();
  });

  it('surfaces a partial-catch-up notice per docs/PRD.md § 7.6 -- never silently implies full catch-up', () => {
    render(
      <DataFreshnessBanner
        freshness={refreshed}
        isLoading={false}
        error={null}
        lastRefreshResult={partialResult}
      />,
    );

    expect(screen.getByText(/only partially caught up/i)).toBeInTheDocument();
    expect(screen.getByText(/click refresh again to continue/i)).toBeInTheDocument();
  });

  it('shows no partial-catch-up notice when the last refresh fully caught up', () => {
    render(
      <DataFreshnessBanner
        freshness={refreshed}
        isLoading={false}
        error={null}
        lastRefreshResult={fullResult}
      />,
    );

    expect(screen.queryByText(/partially caught up/i)).not.toBeInTheDocument();
  });
});
