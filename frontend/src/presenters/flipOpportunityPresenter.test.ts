import { describe, expect, it } from 'vitest';
import {
  classifyMargin,
  formatMargin,
  formatProfit,
  formatQuantity,
  formatVolume,
} from './flipOpportunityPresenter';

describe('classifyMargin', () => {
  // Provisional threshold (docs/TECH_STACK.md notes this is TBD once real
  // data ranges are visible -- the mockup's own four example rows don't
  // encode a consistent margin-based rule).
  it('classifies margins at or above 50% as "up"', () => {
    expect(classifyMargin(97.84)).toBe('up');
    expect(classifyMargin(50)).toBe('up');
  });

  it('classifies margins below 50% as "mid"', () => {
    expect(classifyMargin(49.9)).toBe('mid');
    expect(classifyMargin(7)).toBe('mid');
  });
});

describe('formatMargin', () => {
  it('formats a positive margin with a + sign and rounds to a whole percent', () => {
    expect(formatMargin(97.84)).toEqual({ text: '+98%', colorClass: 'up' });
  });

  it('formats a small margin as "mid"', () => {
    expect(formatMargin(7.2)).toEqual({ text: '+7%', colorClass: 'mid' });
  });

  it('formats a zero margin without a + sign issue', () => {
    expect(formatMargin(0)).toEqual({ text: '+0%', colorClass: 'mid' });
  });
});

describe('formatProfit', () => {
  it('formats profit to 2 decimal places with a + sign, colored by margin', () => {
    expect(formatProfit(0.9784, 97.84)).toEqual({ text: '+0.98', colorClass: 'up' });
  });

  it('colors profit "mid" when the margin is below the threshold, regardless of profit size', () => {
    expect(formatProfit(14, 7)).toEqual({ text: '+14.00', colorClass: 'mid' });
  });
});

describe('formatVolume', () => {
  it('abbreviates thousands as "k" with one decimal, trimming a trailing .0', () => {
    expect(formatVolume(1234)).toBe('1.2k');
    expect(formatVolume(2000)).toBe('2k');
  });

  it('abbreviates millions as "M"', () => {
    expect(formatVolume(1_500_000)).toBe('1.5M');
  });

  it('leaves sub-1000 volumes as a plain rounded number', () => {
    expect(formatVolume(999)).toBe('999');
    expect(formatVolume(54)).toBe('54');
  });
});

describe('formatQuantity', () => {
  it('shows exact integers without the ≈ prefix', () => {
    expect(formatQuantity(1)).toBe('1');
    expect(formatQuantity(366)).toBe('366');
  });

  it('shows non-integers with the ≈ prefix, rounded to 2 decimals, trimming trailing zeros', () => {
    expect(formatQuantity(1.9784)).toBe('≈1.98');
    expect(formatQuantity(1.999)).toBe('≈2');
  });
});
