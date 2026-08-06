import { act, renderHook, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchLeagues } from '../api/leagueApi';
import type { League } from '../entities/League';
import { resolveDefaultLeagueId, useLeagueSelection } from './useLeagueSelection';

vi.mock('../api/leagueApi', () => ({
  fetchLeagues: vi.fn(),
}));

const standard: League = { id: 'Standard', name: 'Standard', isDefault: false };
const hardcore: League = { id: 'Hardcore', name: 'Hardcore', isDefault: false };
const allflame: League = { id: 'Allflame', name: 'Allflame', isDefault: true };

afterEach(() => {
  vi.mocked(fetchLeagues).mockReset();
});

describe('resolveDefaultLeagueId', () => {
  it('picks the league flagged isDefault', () => {
    expect(resolveDefaultLeagueId([standard, allflame])).toBe('Allflame');
  });

  it('falls back to the first league when none is flagged default', () => {
    expect(resolveDefaultLeagueId([standard, hardcore])).toBe('Standard');
  });

  it('returns null for an empty list', () => {
    expect(resolveDefaultLeagueId([])).toBeNull();
  });
});

describe('useLeagueSelection', () => {
  it('loads leagues and selects the default on mount', async () => {
    vi.mocked(fetchLeagues).mockResolvedValue([standard, hardcore, allflame]);

    const { result } = renderHook(() => useLeagueSelection());

    expect(result.current.isLoading).toBe(true);

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.leagues).toEqual([standard, hardcore, allflame]);
    expect(result.current.selectedLeague).toEqual(allflame);
  });

  it('surfaces a fetch failure as an error', async () => {
    vi.mocked(fetchLeagues).mockRejectedValue(new Error('network down'));

    const { result } = renderHook(() => useLeagueSelection());

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.error).toBeInstanceOf(Error);
    expect(result.current.leagues).toEqual([]);
  });

  it('keeps the current selection across a refresh if it still exists', async () => {
    vi.mocked(fetchLeagues).mockResolvedValue([standard, hardcore, allflame]);

    const { result } = renderHook(() => useLeagueSelection());
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    act(() => result.current.selectLeague('Hardcore'));
    expect(result.current.selectedLeague).toEqual(hardcore);

    act(() => result.current.refresh());
    await waitFor(() => expect(result.current.isRefreshing).toBe(false));

    expect(result.current.selectedLeague).toEqual(hardcore);
  });

  it('falls back to the default when the current selection disappears on refresh', async () => {
    vi.mocked(fetchLeagues).mockResolvedValueOnce([standard, hardcore, allflame]);

    const { result } = renderHook(() => useLeagueSelection());
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    act(() => result.current.selectLeague('Hardcore'));

    vi.mocked(fetchLeagues).mockResolvedValueOnce([standard, allflame]);
    act(() => result.current.refresh());

    await waitFor(() => expect(result.current.isRefreshing).toBe(false));
    expect(result.current.selectedLeague).toEqual(allflame);
  });
});
