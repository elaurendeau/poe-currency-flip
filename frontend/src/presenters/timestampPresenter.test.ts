import { describe, expect, it } from 'vitest';
import { formatAbsoluteTimestamp } from './timestampPresenter';

describe('formatAbsoluteTimestamp', () => {
  it('formats as YYYY-MM-DD HH:MM:SS.mmm, matching docs/mockups/flip-row-reference.html\'s .stamp exactly', () => {
    const formatted = formatAbsoluteTimestamp('2026-08-06T06:45:07.261Z');

    expect(formatted).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$/);
    expect(formatted).not.toMatch(/ago|AM|PM|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec/i);
  });

  it('zero-pads single-digit month/day/hour/minute/second and milliseconds to 3 digits', () => {
    // A date deliberately chosen so every component is single-digit except
    // the year, to catch a formatter that forgets to pad any one of them.
    const formatted = formatAbsoluteTimestamp('2026-01-02T03:04:05.006Z');

    // toLocaleString-free local-time formatting means the exact string
    // depends on the runner's timezone offset -- assert the shape (widths
    // and separators), not a fixed value.
    expect(formatted).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$/);
  });
});
