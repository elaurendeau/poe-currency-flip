import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
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
  isRefreshing: boolean;
  error: Error | null;
  refresh: () => void;
}

export function useLeagueSelection(): LeagueSelection {
  const [leagues, setLeagues] = useState<League[]>([]);
  const [selectedLeagueId, setSelectedLeagueId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const isMounted = useRef(true);

  useEffect(() => {
    // Reset on every (re-)mount rather than just once -- React's StrictMode
    // double-invokes effects in development (mount, cleanup, mount again),
    // and without resetting here the cleanup's `false` would stick forever,
    // silently discarding every future state update from loadLeagues.
    isMounted.current = true;
    return () => {
      isMounted.current = false;
    };
  }, []);

  const loadLeagues = useCallback((setPending: (pending: boolean) => void) => {
    setPending(true);
    setError(null);

    fetchLeagues()
      .then((fetchedLeagues) => {
        if (!isMounted.current) return;
        setLeagues(fetchedLeagues);
        // Keep the current selection if it still exists post-refresh (e.g. the
        // user picked Hardcore); only fall back to the default for a brand-new
        // list or one where the previously selected league disappeared.
        setSelectedLeagueId((currentId) =>
          fetchedLeagues.some((league) => league.id === currentId)
            ? currentId
            : resolveDefaultLeagueId(fetchedLeagues),
        );
      })
      .catch((fetchError: Error) => {
        if (isMounted.current) setError(fetchError);
      })
      .finally(() => {
        if (isMounted.current) setPending(false);
      });
  }, []);

  useEffect(() => {
    loadLeagues(setIsLoading);
  }, [loadLeagues]);

  const refresh = useCallback(() => loadLeagues(setIsRefreshing), [loadLeagues]);

  const selectedLeague = useMemo(
    () => leagues.find((league) => league.id === selectedLeagueId) ?? null,
    [leagues, selectedLeagueId],
  );

  return {
    leagues,
    selectedLeague,
    selectLeague: setSelectedLeagueId,
    isLoading,
    isRefreshing,
    error,
    refresh,
  };
}
