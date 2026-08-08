import { describe, expect, it } from 'vitest';
import {
  closestRatioMatches,
  formatAchievedRatio,
  isExactRatioMatch,
  nearbyWholeRatioSuggestions,
  nearestLeftForRight,
  nearestRightForLeft,
  ratioValue,
  simplestIntegerRatio,
} from './ratioCalculatorPresenter';

describe('ratioValue', () => {
  it('parses a colon-separated ratio', () => {
    expect(ratioValue('15.5:1')).toBe(15.5);
  });

  it('parses a slash-separated ratio', () => {
    expect(ratioValue('31/2')).toBe(15.5);
  });

  it('treats a bare number as an implicit :1 ratio', () => {
    expect(ratioValue('15.5')).toBe(15.5);
  });

  it('returns null for a non-numeric input', () => {
    expect(ratioValue('abc')).toBeNull();
  });

  it('returns null for a zero or negative side', () => {
    expect(ratioValue('5:0')).toBeNull();
    expect(ratioValue('-5:1')).toBeNull();
  });

  it('returns null for empty input', () => {
    expect(ratioValue('')).toBeNull();
    expect(ratioValue('   ')).toBeNull();
  });

  it('returns null for a malformed separator', () => {
    expect(ratioValue('1:2:3')).toBeNull();
  });
});

describe('simplestIntegerRatio', () => {
  it('reduces a terminating decimal to its smallest whole-number pair', () => {
    expect(simplestIntegerRatio('15.5:1')).toEqual({ left: 31, right: 2 });
  });

  it('reduces a bare decimal number the same way', () => {
    expect(simplestIntegerRatio('15.5')).toEqual({ left: 31, right: 2 });
  });

  it('preserves an already-reduced whole-number ratio exactly, avoiding float drift', () => {
    // 4/3 is a repeating decimal -- dividing it out as a float and re-deriving
    // decimal places from that would corrupt this back to something other than 4:3.
    expect(simplestIntegerRatio('4:3')).toEqual({ left: 4, right: 3 });
  });

  it('reduces a non-coprime whole-number ratio', () => {
    expect(simplestIntegerRatio('10:4')).toEqual({ left: 5, right: 2 });
  });

  it('returns null for invalid input', () => {
    expect(simplestIntegerRatio('nonsense')).toBeNull();
  });
});

describe('nearestRightForLeft / nearestLeftForRight', () => {
  it('rounds to the nearest integer that keeps the ratio', () => {
    expect(nearestRightForLeft(145, 15.5)).toBe(9);
    expect(nearestLeftForRight(9, 15.5)).toBe(140);
  });
});

describe('formatAchievedRatio', () => {
  it('formats the exact ratio of two whole numbers', () => {
    expect(formatAchievedRatio(31, 2)).toBe('15.5');
  });

  it('rounds to 2 decimal places', () => {
    expect(formatAchievedRatio(145, 9)).toBe('16.11');
  });

  it('returns null when the right side is zero', () => {
    expect(formatAchievedRatio(5, 0)).toBeNull();
  });
});

describe('isExactRatioMatch', () => {
  it('is true when the pair lands exactly on the target ratio', () => {
    expect(isExactRatioMatch(31, 2, 15.5)).toBe(true);
  });

  it('is false when rounding produced a different ratio', () => {
    expect(isExactRatioMatch(145, 9, 15.5)).toBe(false);
  });
});

describe('closestRatioMatches', () => {
  it('offers both the round-down and round-up counterpart for a left anchor', () => {
    expect(closestRatioMatches(15.5, 'left', 145)).toEqual([
      { left: 145, right: 9, achievedRatio: '16.11' },
      { left: 145, right: 10, achievedRatio: '14.5' },
    ]);
  });

  it('offers both the round-down and round-up counterpart for a right anchor', () => {
    expect(closestRatioMatches(15.5, 'right', 7)).toEqual([
      { left: 108, right: 7, achievedRatio: '15.43' },
      { left: 109, right: 7, achievedRatio: '15.57' },
    ]);
  });

  it('drops a zero or negative counterpart rather than offering a meaningless pair', () => {
    // 1/15.5 rounds down to 0, which isn't a usable ratio side.
    expect(closestRatioMatches(15.5, 'left', 1)).toEqual([{ left: 1, right: 1, achievedRatio: '1' }]);
  });
});

describe('nearbyWholeRatioSuggestions', () => {
  it('offers the ceiling and floor whole ratios, holding the left anchor fixed', () => {
    expect(nearbyWholeRatioSuggestions(15.5, 'left', 145)).toEqual([
      { ratio: 16, left: 145, right: 9 },
      { ratio: 15, left: 145, right: 10 },
    ]);
  });

  it('offers the ceiling and floor whole ratios, holding the right anchor fixed', () => {
    expect(nearbyWholeRatioSuggestions(15.5, 'right', 7)).toEqual([
      { ratio: 16, left: 112, right: 7 },
      { ratio: 15, left: 105, right: 7 },
    ]);
  });

  it('returns no suggestions when the target ratio is already a whole number', () => {
    expect(nearbyWholeRatioSuggestions(15, 'left', 145)).toEqual([]);
  });
});
