import { act, renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { useTechniqueFilters } from './useTechniqueFilters';

describe('useTechniqueFilters', () => {
  it('starts with every technique enabled -- filtering is opt-out, not opt-in', () => {
    const { result } = renderHook(() => useTechniqueFilters());

    expect(result.current.enabledTechniques).toEqual({
      VENDOR_RECIPE: true,
      EXCHANGE_SPREAD: true,
      DIVINATION_CARD: true,
      BULK_BUY: true,
    });
  });

  it('toggles a single technique without affecting the others', () => {
    const { result } = renderHook(() => useTechniqueFilters());

    act(() => result.current.toggleTechnique('BULK_BUY'));

    expect(result.current.enabledTechniques).toEqual({
      VENDOR_RECIPE: true,
      EXCHANGE_SPREAD: true,
      DIVINATION_CARD: true,
      BULK_BUY: false,
    });

    act(() => result.current.toggleTechnique('BULK_BUY'));

    expect(result.current.enabledTechniques.BULK_BUY).toBe(true);
  });
});
