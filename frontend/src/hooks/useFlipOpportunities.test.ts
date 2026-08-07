import { renderHook, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchFlipOpportunities } from '../api/flipOpportunityApi';
import type { FlipOpportunity } from '../entities/FlipOpportunity';
import { useFlipOpportunities } from './useFlipOpportunities';

vi.mock('../api/flipOpportunityApi', () => ({
  fetchFlipOpportunities: vi.fn(),
}));

const opportunity: FlipOpportunity = {
  technique: 'EXCHANGE_SPREAD',
  start: [{ currencyId: 'A', name: 'Chaos Orb', iconUrl: null, itemType: 'CURRENCY', quantity: 1 }],
  via: [{ currencyId: 'B', name: 'Scroll of Wisdom', iconUrl: null, itemType: 'CURRENCY', quantity: 366 }],
  sell: [{ currencyId: 'A', name: 'Chaos Orb', iconUrl: null, itemType: 'CURRENCY', quantity: 1.9784 }],
  marginPercent: 97.84,
  profit: { currencyId: 'A', name: 'Chaos Orb', iconUrl: null, itemType: 'CURRENCY', quantity: 0.9784 },
  volume: 1234,
  detail: 'buy 365:1 · sell 186:1',
};

afterEach(() => {
  vi.mocked(fetchFlipOpportunities).mockReset();
});

describe('useFlipOpportunities', () => {
  it('loads opportunities for the given league on mount', async () => {
    vi.mocked(fetchFlipOpportunities).mockResolvedValue([opportunity]);

    const { result } = renderHook(() => useFlipOpportunities('Standard'));

    expect(result.current.isLoading).toBe(true);

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.opportunities).toEqual([opportunity]);
    expect(fetchFlipOpportunities).toHaveBeenCalledWith('Standard');
  });

  it('surfaces a fetch failure as an error', async () => {
    vi.mocked(fetchFlipOpportunities).mockRejectedValue(new Error('network down'));

    const { result } = renderHook(() => useFlipOpportunities('Standard'));

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.error).toBeInstanceOf(Error);
    expect(result.current.opportunities).toEqual([]);
  });

  it('short-circuits to an empty, non-loading state when no league is selected yet', () => {
    const { result } = renderHook(() => useFlipOpportunities(null));

    expect(result.current.isLoading).toBe(false);
    expect(result.current.opportunities).toEqual([]);
    expect(fetchFlipOpportunities).not.toHaveBeenCalled();
  });

  it('re-fetches when the league id changes', async () => {
    vi.mocked(fetchFlipOpportunities).mockResolvedValue([opportunity]);

    const { rerender } = renderHook(({ leagueId }) => useFlipOpportunities(leagueId), {
      initialProps: { leagueId: 'Standard' as string | null },
    });

    await waitFor(() => expect(fetchFlipOpportunities).toHaveBeenCalledWith('Standard'));

    rerender({ leagueId: 'Hardcore' });

    await waitFor(() => expect(fetchFlipOpportunities).toHaveBeenCalledWith('Hardcore'));
  });
});
