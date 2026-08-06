import { useCallback, useEffect, useRef, useState } from 'react';
import { fetchIngestionFreshness, refreshIngestion } from '../api/ingestionApi';
import type { IngestionFreshness, IngestionRefreshResult } from '../entities/IngestionFreshness';

export interface IngestionFreshnessState {
  freshness: IngestionFreshness | null;
  isLoading: boolean;
  isRefreshing: boolean;
  error: Error | null;
  // Only set after a refresh triggered in this session -- not persisted, and
  // not implied by freshness alone (docs/PRD.md § 7.6: the UI must indicate
  // when a refresh completed only partially, not silently imply full
  // catch-up from a click).
  lastRefreshResult: IngestionRefreshResult | null;
  refresh: () => void;
}

export function useIngestionFreshness(): IngestionFreshnessState {
  const [freshness, setFreshness] = useState<IngestionFreshness | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [lastRefreshResult, setLastRefreshResult] = useState<IngestionRefreshResult | null>(null);
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
    fetchIngestionFreshness()
      .then((result) => {
        if (isMounted.current) setFreshness(result);
      })
      .catch((fetchError: Error) => {
        if (isMounted.current) setError(fetchError);
      })
      .finally(() => {
        if (isMounted.current) setIsLoading(false);
      });
  }, []);

  const refresh = useCallback(() => {
    setIsRefreshing(true);
    setError(null);

    refreshIngestion()
      .then((result) => {
        if (!isMounted.current) return;
        setLastRefreshResult(result);
        // The refresh response itself carries lastProcessedChangeId but not
        // activeGenerationRefreshedAt -- re-fetch freshness for the
        // authoritative server-side commit timestamp rather than
        // approximating it with the client's current time.
        return fetchIngestionFreshness().then((freshnessResult) => {
          if (isMounted.current) setFreshness(freshnessResult);
        });
      })
      .catch((refreshError: Error) => {
        if (isMounted.current) setError(refreshError);
      })
      .finally(() => {
        if (isMounted.current) setIsRefreshing(false);
      });
  }, []);

  return { freshness, isLoading, isRefreshing, error, lastRefreshResult, refresh };
}
