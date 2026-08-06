import { renderHook, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import leaguesResponseFixture from '../api/__fixtures__/leagues-response.json';
import { useLeagueSelection } from './useLeagueSelection';

// Unlike useLeagueSelection.test.ts (which mocks the gateway function to
// isolate orchestration logic), this exercises the real pipeline end to
// end -- a saved real Leagues API response, through the real fetch call,
// through the real gateway's parsing, into the real hook -- so the whole
// composed stack is verified against real data, not just each piece in
// isolation.
afterEach(() => {
  vi.unstubAllGlobals();
});

describe('useLeagueSelection (integration, real fixture)', () => {
  it('loads and selects the default league from a real captured API response', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve(leaguesResponseFixture),
      }),
    );

    const { result } = renderHook(() => useLeagueSelection());

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.error).toBeNull();
    expect(result.current.leagues).toHaveLength(leaguesResponseFixture.length);
    expect(result.current.selectedLeague).toEqual({
      id: 'Allflame',
      name: 'Allflame',
      isDefault: true,
    });
  });
});
