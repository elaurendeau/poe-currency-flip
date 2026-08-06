import { act, renderHook, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchIngestionFreshness, refreshIngestion } from '../api/ingestionApi';
import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';
import { useIngestionFreshness } from './useIngestionFreshness';

vi.mock('../api/ingestionApi', () => ({
  fetchIngestionFreshness: vi.fn(),
  refreshIngestion: vi.fn(),
}));

const neverRefreshed: IngestionFreshness = { lastProcessedChangeId: null, activeGenerationRefreshedAt: null };
const refreshedOnce: IngestionFreshness = {
  lastProcessedChangeId: 1785996000,
  activeGenerationRefreshedAt: '2026-08-06T06:45:07.261123Z',
};
const fullyCaughtUpResult: IngestionRefreshResult = {
  hoursProcessed: 24,
  fullyCaughtUp: true,
  lastProcessedChangeId: 1785996000,
  skippedUnresolvableMarketEntryCount: 3796,
};
const partialResult: IngestionRefreshResult = {
  hoursProcessed: 48,
  fullyCaughtUp: false,
  lastProcessedChangeId: 1785900000,
  skippedUnresolvableMarketEntryCount: 12,
};

afterEach(() => {
  vi.mocked(fetchIngestionFreshness).mockReset();
  vi.mocked(refreshIngestion).mockReset();
});

describe('useIngestionFreshness', () => {
  it('loads freshness on mount', async () => {
    vi.mocked(fetchIngestionFreshness).mockResolvedValue(neverRefreshed);

    const { result } = renderHook(() => useIngestionFreshness());

    expect(result.current.isLoading).toBe(true);

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.freshness).toEqual(neverRefreshed);
    expect(result.current.lastRefreshResult).toBeNull();
  });

  it('surfaces a fetch failure as an error', async () => {
    vi.mocked(fetchIngestionFreshness).mockRejectedValue(new Error('network down'));

    const { result } = renderHook(() => useIngestionFreshness());

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.error).toBeInstanceOf(Error);
    expect(result.current.freshness).toBeNull();
  });

  it('refresh() posts the refresh, then re-fetches freshness for the authoritative timestamp', async () => {
    vi.mocked(fetchIngestionFreshness).mockResolvedValueOnce(neverRefreshed);
    const { result } = renderHook(() => useIngestionFreshness());
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    vi.mocked(refreshIngestion).mockResolvedValue(fullyCaughtUpResult);
    vi.mocked(fetchIngestionFreshness).mockResolvedValueOnce(refreshedOnce);

    act(() => result.current.refresh());
    await waitFor(() => expect(result.current.isRefreshing).toBe(false));

    expect(result.current.freshness).toEqual(refreshedOnce);
    expect(result.current.lastRefreshResult).toEqual(fullyCaughtUpResult);
  });

  it('surfaces fullyCaughtUp: false from a partial refresh so the UI can prompt another click', async () => {
    vi.mocked(fetchIngestionFreshness).mockResolvedValueOnce(neverRefreshed);
    const { result } = renderHook(() => useIngestionFreshness());
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    vi.mocked(refreshIngestion).mockResolvedValue(partialResult);
    vi.mocked(fetchIngestionFreshness).mockResolvedValueOnce(refreshedOnce);

    act(() => result.current.refresh());
    await waitFor(() => expect(result.current.isRefreshing).toBe(false));

    expect(result.current.lastRefreshResult).toEqual(partialResult);
    expect(result.current.lastRefreshResult?.fullyCaughtUp).toBe(false);
  });

  it('surfaces a refresh failure as an error without touching freshness', async () => {
    vi.mocked(fetchIngestionFreshness).mockResolvedValueOnce(neverRefreshed);
    const { result } = renderHook(() => useIngestionFreshness());
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    vi.mocked(refreshIngestion).mockRejectedValue(new Error('refresh failed'));

    act(() => result.current.refresh());
    await waitFor(() => expect(result.current.isRefreshing).toBe(false));

    expect(result.current.error).toBeInstanceOf(Error);
    expect(result.current.freshness).toEqual(neverRefreshed);
  });
});
