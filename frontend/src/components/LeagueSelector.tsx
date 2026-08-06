import type { League } from '../entities/League';

interface LeagueSelectorProps {
  leagues: League[];
  selectedLeague: League | null;
  onSelect: (leagueId: string) => void;
  isLoading: boolean;
  error: Error | null;
}

export function LeagueSelector({
  leagues,
  selectedLeague,
  onSelect,
  isLoading,
  error,
}: LeagueSelectorProps) {
  if (error) {
    return <span className="league-selector league-selector--error">Failed to load leagues</span>;
  }

  if (isLoading) {
    return <span className="league-selector league-selector--loading">Loading leagues…</span>;
  }

  return (
    <select
      className="league-selector"
      value={selectedLeague?.id ?? ''}
      onChange={(event) => onSelect(event.target.value)}
      aria-label="League"
    >
      {leagues.map((league) => (
        <option key={league.id} value={league.id}>
          {league.name}
        </option>
      ))}
    </select>
  );
}
