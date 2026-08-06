import { act, renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { useFavoriteRoutes } from './useFavoriteRoutes';

afterEach(() => {
  window.localStorage.clear();
});

describe('useFavoriteRoutes', () => {
  it('starts with no favorites', () => {
    const { result } = renderHook(() => useFavoriteRoutes());

    expect(result.current.favoriteRouteKeys.size).toBe(0);
    expect(result.current.isFavorite('a|b|c|d')).toBe(false);
  });

  it('toggling a route key on marks it favorite', () => {
    const { result } = renderHook(() => useFavoriteRoutes());

    act(() => result.current.toggleFavorite('a|b|c|d'));

    expect(result.current.isFavorite('a|b|c|d')).toBe(true);
  });

  it('toggling an already-favorited route key removes it', () => {
    const { result } = renderHook(() => useFavoriteRoutes());

    act(() => result.current.toggleFavorite('a|b|c|d'));
    act(() => result.current.toggleFavorite('a|b|c|d'));

    expect(result.current.isFavorite('a|b|c|d')).toBe(false);
  });

  it('persists favorites to localStorage and reloads them on a fresh mount', () => {
    const { result, unmount } = renderHook(() => useFavoriteRoutes());

    act(() => result.current.toggleFavorite('route-1'));
    unmount();

    const { result: secondMount } = renderHook(() => useFavoriteRoutes());

    expect(secondMount.current.isFavorite('route-1')).toBe(true);
  });

  it('tolerates corrupted localStorage content by starting empty', () => {
    window.localStorage.setItem('poe-flip-finder:favorite-routes', '{not valid json');

    const { result } = renderHook(() => useFavoriteRoutes());

    expect(result.current.favoriteRouteKeys.size).toBe(0);
  });
});
