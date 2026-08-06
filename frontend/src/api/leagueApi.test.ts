import { afterEach, describe, expect, it, vi } from 'vitest';
import leaguesResponseFixture from './__fixtures__/leagues-response.json';
import { fetchLeagues, LeagueApiError } from './leagueApi';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('fetchLeagues', () => {
  it('normalizes a real Leagues API response into League entities', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve(leaguesResponseFixture),
      }),
    );

    const leagues = await fetchLeagues();

    expect(leagues).toEqual([
      { id: 'Standard', name: 'Standard', isDefault: false },
      { id: 'Hardcore', name: 'Hardcore', isDefault: false },
      { id: 'Ruthless', name: 'Ruthless', isDefault: false },
      { id: 'Hardcore Ruthless', name: 'Hardcore Ruthless', isDefault: false },
      { id: 'Allflame', name: 'Allflame', isDefault: true },
      { id: 'Hardcore Allflame', name: 'Hardcore Allflame', isDefault: false },
      { id: 'Ruthless Allflame', name: 'Ruthless Allflame', isDefault: false },
      { id: 'HC Ruthless Allflame', name: 'HC Ruthless Allflame', isDefault: false },
    ]);
  });

  it('throws LeagueApiError when the response is not ok', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: false, status: 500, json: () => Promise.resolve([]) }),
    );

    await expect(fetchLeagues()).rejects.toBeInstanceOf(LeagueApiError);
  });
});
