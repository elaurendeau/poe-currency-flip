import { useEffect, useMemo, useState } from 'react';
import { fetchLeagues } from '../api/leagueApi';
import type { League } from '../entities/League';

export function resolveDefaultLeagueId(leagues: League[]): string | null {
  return leagues.find((league) => league.isDefault)?.id ?? leagues[0]?.id ?? null;
}

export interface LeagueSelection {
  leagues: League[];
  selectedLeague: League | null;
  selectLeague: (leagueId: string) => void;
  isLoading: boolean;
  error: Error | null;
}

export function useLeagueSelection(): LeagueSelection {
  const [leagues, setLeagues] = useState<League[]>([]);
  const [selectedLeagueId, setSelectedLeagueId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let cancelled = false;

    fetchLeagues()
      .then((fetchedLeagues) => {
        if (cancelled) return;
        setLeagues(fetchedLeagues);
        setSelectedLeagueId(resolveDefaultLeagueId(fetchedLeagues));
      })
      .catch((fetchError: Error) => {
        if (cancelled) return;
        setError(fetchError);
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const selectedLeague = useMemo(
    () => leagues.find((league) => league.id === selectedLeagueId) ?? null,
    [leagues, selectedLeagueId],
  );

  return { leagues, selectedLeague, selectLeague: setSelectedLeagueId, isLoading, error };
}
