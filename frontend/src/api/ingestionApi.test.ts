import { afterEach, describe, expect, it, vi } from 'vitest';
import neverRefreshedFixture from './__fixtures__/ingestion-freshness-response-never-refreshed.json';
import freshnessFixture from './__fixtures__/ingestion-freshness-response.json';
import refreshResultFixture from './__fixtures__/ingestion-refresh-response.json';
import { fetchIngestionFreshness, IngestionApiError, refreshIngestion } from './ingestionApi';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('fetchIngestionFreshness', () => {
  it('normalizes a real Freshness API response into an IngestionFreshness entity', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve(freshnessFixture),
      }),
    );

    const freshness = await fetchIngestionFreshness();

    expect(freshness).toEqual({
      lastProcessedChangeId: 1785996000,
      activeGenerationRefreshedAt: '2026-08-06T06:45:07.261123Z',
    });
  });

  it('normalizes a never-refreshed response (both fields null) correctly', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve(neverRefreshedFixture),
      }),
    );

    const freshness = await fetchIngestionFreshness();

    expect(freshness).toEqual({ lastProcessedChangeId: null, activeGenerationRefreshedAt: null });
  });

  it('throws IngestionApiError when the response is not ok', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: false, status: 500, json: () => Promise.resolve({}) }),
    );

    await expect(fetchIngestionFreshness()).rejects.toBeInstanceOf(IngestionApiError);
  });
});

describe('refreshIngestion', () => {
  it('normalizes a real refresh response and posts to the right endpoint', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve(refreshResultFixture),
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await refreshIngestion();

    expect(result).toEqual({
      hoursProcessed: 24,
      fullyCaughtUp: true,
      lastProcessedChangeId: 1785996000,
      skippedUnresolvableMarketEntryCount: 3796,
    });
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining('/exchange-ingestion/refresh'), {
      method: 'POST',
    });
  });

  it('throws IngestionApiError when the response is not ok', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: false, status: 502, json: () => Promise.resolve({}) }),
    );

    await expect(refreshIngestion()).rejects.toBeInstanceOf(IngestionApiError);
  });
});
