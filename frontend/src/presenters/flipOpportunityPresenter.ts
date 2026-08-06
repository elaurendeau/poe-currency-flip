// Provisional -- docs/TECH_STACK.md notes the up/mid color threshold is
// TBD once real data ranges are visible; the mockup's own four example
// rows don't encode a single consistent margin-based rule.
const MARGIN_COLOR_THRESHOLD = 50;

export type ColorClass = 'up' | 'mid';

export function classifyMargin(marginPercent: number): ColorClass {
  return marginPercent >= MARGIN_COLOR_THRESHOLD ? 'up' : 'mid';
}

export function formatMargin(marginPercent: number): { text: string; colorClass: ColorClass } {
  const rounded = Math.round(marginPercent);
  const sign = rounded >= 0 ? '+' : '';
  return { text: `${sign}${rounded}%`, colorClass: classifyMargin(marginPercent) };
}

export function formatProfit(profit: number, marginPercent: number): { text: string; colorClass: ColorClass } {
  const sign = profit >= 0 ? '+' : '';
  return { text: `${sign}${profit.toFixed(2)}`, colorClass: classifyMargin(marginPercent) };
}

export function formatVolume(volume: number): string {
  if (volume >= 1_000_000) {
    return `${trimTrailingZeros(volume / 1_000_000, 1)}M`;
  }
  if (volume >= 1000) {
    return `${trimTrailingZeros(volume / 1000, 1)}k`;
  }
  return Math.round(volume).toString();
}

export function formatQuantity(quantity: number): string {
  if (Number.isInteger(quantity)) {
    return quantity.toString();
  }
  return `≈${trimTrailingZeros(quantity, 2)}`;
}

function trimTrailingZeros(value: number, decimals: number): string {
  return Number(value.toFixed(decimals)).toString();
}
