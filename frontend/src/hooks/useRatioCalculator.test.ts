import { act, renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { useRatioCalculator } from './useRatioCalculator';

describe('useRatioCalculator', () => {
  it('starts closed', () => {
    const { result } = renderHook(() => useRatioCalculator());

    expect(result.current.isOpen).toBe(false);
  });

  it('toggleOpen flips open state, and close forces it shut', () => {
    const { result } = renderHook(() => useRatioCalculator());

    act(() => result.current.toggleOpen());
    expect(result.current.isOpen).toBe(true);

    act(() => result.current.toggleOpen());
    expect(result.current.isOpen).toBe(false);

    act(() => result.current.toggleOpen());
    act(() => result.current.close());
    expect(result.current.isOpen).toBe(false);
  });

  it('starts empty and invalid', () => {
    const { result } = renderHook(() => useRatioCalculator());

    expect(result.current.ratioText).toBe('');
    expect(result.current.leftText).toBe('');
    expect(result.current.rightText).toBe('');
    expect(result.current.isRatioValid).toBe(false);
  });

  it('fills left/right with the smallest whole-number pair when a valid ratio is entered', () => {
    const { result } = renderHook(() => useRatioCalculator());

    act(() => result.current.setRatioText('15.5:1'));

    expect(result.current.isRatioValid).toBe(true);
    expect(result.current.leftText).toBe('31');
    expect(result.current.rightText).toBe('2');
    expect(result.current.isExactMatch).toBe(true);
    expect(result.current.closestMatches).toEqual([]);
    expect(result.current.suggestions).toEqual([]);
  });

  it('recalculates right when left is edited, and reports both closest matches', () => {
    const { result } = renderHook(() => useRatioCalculator());
    act(() => result.current.setRatioText('15.5:1'));

    act(() => result.current.setLeftText('145'));

    expect(result.current.rightText).toBe('9');
    expect(result.current.isExactMatch).toBe(false);
    expect(result.current.closestMatches).toEqual([
      { left: 145, right: 9, achievedRatio: '16.11' },
      { left: 145, right: 10, achievedRatio: '14.5' },
    ]);
    expect(result.current.suggestions).toEqual([
      { ratio: 16, left: 145, right: 9 },
      { ratio: 15, left: 145, right: 10 },
    ]);
  });

  it('recalculates left when right is edited, anchoring closest matches and suggestions on the right value', () => {
    const { result } = renderHook(() => useRatioCalculator());
    act(() => result.current.setRatioText('15.5:1'));

    act(() => result.current.setRightText('7'));

    expect(result.current.leftText).toBe('109');
    expect(result.current.closestMatches).toEqual([
      { left: 108, right: 7, achievedRatio: '15.43' },
      { left: 109, right: 7, achievedRatio: '15.57' },
    ]);
    expect(result.current.suggestions).toEqual([
      { ratio: 16, left: 112, right: 7 },
      { ratio: 15, left: 105, right: 7 },
    ]);
  });

  it('clears back to no suggestions once the ratio text changes back to an exact match', () => {
    const { result } = renderHook(() => useRatioCalculator());
    act(() => result.current.setRatioText('15.5:1'));
    act(() => result.current.setLeftText('145'));

    // Different text than before ('31:2' vs '15.5:1') so the ratioText state
    // actually changes and the reset effect fires -- React bails out of a
    // set-to-the-same-value call, so re-typing the identical string wouldn't.
    act(() => result.current.setRatioText('31:2'));

    expect(result.current.leftText).toBe('31');
    expect(result.current.rightText).toBe('2');
    expect(result.current.isExactMatch).toBe(true);
    expect(result.current.closestMatches).toEqual([]);
    expect(result.current.suggestions).toEqual([]);
  });

  it('still offers both closest matches, but no whole-ratio suggestions, when the target ratio is itself whole', () => {
    const { result } = renderHook(() => useRatioCalculator());
    act(() => result.current.setRatioText('15:1'));

    act(() => result.current.setLeftText('145'));

    expect(result.current.isExactMatch).toBe(false);
    expect(result.current.closestMatches).toEqual([
      { left: 145, right: 9, achievedRatio: '16.11' },
      { left: 145, right: 10, achievedRatio: '14.5' },
    ]);
    expect(result.current.suggestions).toEqual([]);
  });

  it('treats an invalid ratio as invalid without recalculating the other field', () => {
    const { result } = renderHook(() => useRatioCalculator());

    act(() => result.current.setRatioText('15.5:x'));

    expect(result.current.isRatioValid).toBe(false);
    expect(result.current.achievedRatio).toBeNull();
  });
});
