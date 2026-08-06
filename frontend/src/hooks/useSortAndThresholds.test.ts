import { act, renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { useSortAndThresholds } from './useSortAndThresholds';

describe('useSortAndThresholds', () => {
  it('defaults to sorting by Margin descending, matching the mockup', () => {
    const { result } = renderHook(() => useSortAndThresholds());

    expect(result.current.sortColumn).toBe('margin');
    expect(result.current.sortDirection).toBe('desc');
  });

  it('toggles direction when the same column is clicked again', () => {
    const { result } = renderHook(() => useSortAndThresholds());

    act(() => result.current.toggleSort('margin'));
    expect(result.current.sortDirection).toBe('asc');

    act(() => result.current.toggleSort('margin'));
    expect(result.current.sortDirection).toBe('desc');
  });

  it('switches to a new column defaulting to descending', () => {
    const { result } = renderHook(() => useSortAndThresholds());

    act(() => result.current.toggleSort('margin'));
    act(() => result.current.toggleSort('volume'));

    expect(result.current.sortColumn).toBe('volume');
    expect(result.current.sortDirection).toBe('desc');
  });

  it('starts with no thresholds set', () => {
    const { result } = renderHook(() => useSortAndThresholds());

    expect(result.current.thresholds).toEqual({});
  });

  it('sets a threshold for a column independently of the others', () => {
    const { result } = renderHook(() => useSortAndThresholds());

    act(() => result.current.setThreshold('volume', 50));

    expect(result.current.thresholds).toEqual({ volume: 50 });
  });

  it('clears a threshold when set to null', () => {
    const { result } = renderHook(() => useSortAndThresholds());

    act(() => result.current.setThreshold('volume', 50));
    act(() => result.current.setThreshold('volume', null));

    expect(result.current.thresholds).toEqual({});
  });
});
