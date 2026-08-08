export interface IntegerRatio {
  left: number;
  right: number;
}

interface RatioTextParts {
  leftText: string;
  rightText: string;
}

function gcd(a: number, b: number): number {
  let x = Math.abs(a);
  let y = Math.abs(b);
  while (y) {
    [x, y] = [y, x % y];
  }
  return x || 1;
}

function decimalPlacesOf(text: string): number {
  if (!text.includes('.')) return 0;
  return text.split('.')[1].replace(/0+$/, '').length;
}

function splitRatioText(raw: string): RatioTextParts | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;

  const parts = trimmed.split(/[:/]/).map((part) => part.trim());
  if (parts.length > 2 || parts.some((part) => part === '')) return null;

  const leftText = parts[0];
  const rightText = parts.length === 2 ? parts[1] : '1';
  const leftNum = Number(leftText);
  const rightNum = Number(rightText);
  if (!Number.isFinite(leftNum) || !Number.isFinite(rightNum) || leftNum <= 0 || rightNum <= 0) {
    return null;
  }

  return { leftText, rightText };
}

// Ratio input as a plain number, e.g. "15.5:1" or "31:2" or "15.5" -> 15.5.
export function ratioValue(raw: string): number | null {
  const parts = splitRatioText(raw);
  if (!parts) return null;
  return Number(parts.leftText) / Number(parts.rightText);
}

// Smallest whole-number pair matching the entered ratio exactly, derived from
// the input's own decimal places rather than a divided-out float -- avoids
// precision drift for ratios like 4:3 that don't terminate as a decimal.
export function simplestIntegerRatio(raw: string): IntegerRatio | null {
  const parts = splitRatioText(raw);
  if (!parts) return null;

  const decimalPlaces = Math.max(decimalPlacesOf(parts.leftText), decimalPlacesOf(parts.rightText));
  const scale = 10 ** decimalPlaces;
  const scaledLeft = Math.round(Number(parts.leftText) * scale);
  const scaledRight = Math.round(Number(parts.rightText) * scale);
  const divisor = gcd(scaledLeft, scaledRight);

  return { left: scaledLeft / divisor, right: scaledRight / divisor };
}

export function nearestRightForLeft(left: number, ratio: number): number {
  return Math.round(left / ratio);
}

export function nearestLeftForRight(right: number, ratio: number): number {
  return Math.round(right * ratio);
}

// The ratio actually achieved by two whole numbers, for feedback when they
// don't land exactly on the requested ratio (e.g. after rounding to nearest).
export function formatAchievedRatio(left: number, right: number): string | null {
  if (!Number.isFinite(left) || !Number.isFinite(right) || right === 0) return null;
  const rounded = Math.round((left / right) * 100) / 100;
  return String(rounded);
}

// Whether left/right land exactly on the target ratio, compared at the same
// 2-decimal precision formatAchievedRatio displays -- avoids float noise from
// the two independent divisions (achieved vs. parsed target) disagreeing on
// digits the UI doesn't show anyway.
export function isExactRatioMatch(left: number, right: number, ratio: number): boolean {
  const achieved = formatAchievedRatio(left, right);
  if (achieved === null) return false;
  return Number(achieved) === Math.round(ratio * 100) / 100;
}

export type RatioAnchor = 'left' | 'right';

export interface RatioSuggestion {
  ratio: number;
  left: number;
  right: number;
}

export interface ClosestMatch {
  left: number;
  right: number;
  achievedRatio: string;
}

// The two whole-number candidates that bracket the target ratio for the
// anchored field -- rounding the counterpart down (overshoots the ratio) and
// up (undershoots it). Always both, never just whichever rounds "nearest",
// since either direction can be the one the player actually wants to list at.
export function closestRatioMatches(ratio: number, anchor: RatioAnchor, anchorValue: number): ClosestMatch[] {
  const quotient = anchor === 'left' ? anchorValue / ratio : anchorValue * ratio;
  const counterparts = [Math.floor(quotient), Math.ceil(quotient)].filter(
    (value, index, all) => value > 0 && all.indexOf(value) === index,
  );

  return counterparts.map((counterpart) => {
    const left = anchor === 'left' ? anchorValue : counterpart;
    const right = anchor === 'left' ? counterpart : anchorValue;
    return { left, right, achievedRatio: formatAchievedRatio(left, right) ?? '' };
  });
}

// Alternatives at the nearest whole-number ratios above and below the target,
// holding whichever field the user last edited (the anchor) fixed -- lets the
// user trade exactness for a rounder ratio. Empty when the target ratio is
// already a whole number, since there's nothing nearby to offer.
export function nearbyWholeRatioSuggestions(
  ratio: number,
  anchor: RatioAnchor,
  anchorValue: number,
): RatioSuggestion[] {
  const floorRatio = Math.floor(ratio);
  const ceilRatio = Math.ceil(ratio);
  if (floorRatio === ceilRatio) return [];

  return [ceilRatio, floorRatio].map((candidate) => ({
    ratio: candidate,
    left: anchor === 'left' ? anchorValue : nearestLeftForRight(anchorValue, candidate),
    right: anchor === 'right' ? anchorValue : nearestRightForLeft(anchorValue, candidate),
  }));
}
