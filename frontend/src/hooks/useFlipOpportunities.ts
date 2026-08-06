import { useEffect, useRef, useState } from 'react';
import { fetchFlipOpportunities } from '../api/flipOpportunityApi';
import type { FlipOpportunity } from '../entities/FlipOpportunity';

export interface FlipOpportunitiesState {
  opportunities: FlipOpportunity[];
  isLoading: boolean;
  error: Error | null;
}

export function useFlipOpportunities(leagueId: string | null): FlipOpportunitiesState {
  const [opportunities, setOpportunities] = useState<FlipOpportunity[]>([]);
  const [isLoading, setIsLoading] = useState(leagueId !== null);
  const [error, setError] = useState<Error | null>(null);
  const isMounted = useRef(true);

  useEffect(() => {
    // Reset on every (re-)mount -- React's StrictMode double-invokes effects
    // in development (mount, cleanup, mount again), and without resetting
    // here the cleanup's `false` would stick forever, silently discarding
    // every future state update below.
    isMounted.current = true;
    return () => {
      isMounted.current = false;
    };
  }, []);

  useEffect(() => {
    if (leagueId === null) {
      setOpportunities([]);
      setIsLoading(false);
      setError(null);
      return;
    }

    setIsLoading(true);
    setError(null);

    fetchFlipOpportunities(leagueId)
      .then((result) => {
        if (isMounted.current) setOpportunities(result);
      })
      .catch((fetchError: Error) => {
        if (isMounted.current) setError(fetchError);
      })
      .finally(() => {
        if (isMounted.current) setIsLoading(false);
      });
  }, [leagueId]);

  return { opportunities, isLoading, error };
}
