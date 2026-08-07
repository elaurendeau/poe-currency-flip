// docs/PRD.md § 7.6: an absolute timestamp, not a vague relative time --
// full date, hour, minute, and millisecond. Format matches
// docs/mockups/flip-row-reference.html's .stamp exactly
// ("2026-08-05 14:32:07.418"): YYYY-MM-DD HH:MM:SS.mmm, 24-hour, local
// time -- not toLocaleString's locale-dependent "Aug 5, 2026, 2:32 PM"
// shape, which matches neither the mockup nor PRD's millisecond
// requirement. Shared by DataFreshnessStamp (§ 7.6) and BuildInfoBar (§ 7.11).
export function formatAbsoluteTimestamp(iso: string): string {
  const date = new Date(iso);
  const pad = (value: number, width = 2) => value.toString().padStart(width, '0');
  const datePart = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  const timePart = `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}.${pad(date.getMilliseconds(), 3)}`;
  return `${datePart} ${timePart}`;
}
