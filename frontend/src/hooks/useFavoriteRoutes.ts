import { useCallback, useEffect, useState } from 'react';

const STORAGE_KEY = 'poe-flip-finder:favorite-routes';

export interface FavoriteRoutes {
  favoriteRouteKeys: Set<string>;
  isFavorite: (routeKey: string) => boolean;
  toggleFavorite: (routeKey: string) => void;
}

function loadFromStorage(): Set<string> {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return new Set();
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return new Set();
    return new Set(parsed.filter((item): item is string => typeof item === 'string'));
  } catch {
    return new Set();
  }
}

// Favorites are a personal, per-browser preference with no user-account
// system -- stored client-side only, per PRD.md § 7.10 / TECH_STACK.md.
export function useFavoriteRoutes(): FavoriteRoutes {
  const [favoriteRouteKeys, setFavoriteRouteKeys] = useState<Set<string>>(loadFromStorage);

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify([...favoriteRouteKeys]));
  }, [favoriteRouteKeys]);

  const toggleFavorite = useCallback((routeKey: string) => {
    setFavoriteRouteKeys((current) => {
      const next = new Set(current);
      if (next.has(routeKey)) {
        next.delete(routeKey);
      } else {
        next.add(routeKey);
      }
      return next;
    });
  }, []);

  const isFavorite = useCallback((routeKey: string) => favoriteRouteKeys.has(routeKey), [favoriteRouteKeys]);

  return { favoriteRouteKeys, isFavorite, toggleFavorite };
}
