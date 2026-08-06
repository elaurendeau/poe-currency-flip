import { LeagueSelector } from './components/LeagueSelector';
import { useLeagueSelection } from './hooks/useLeagueSelection';

function App() {
  const { leagues, selectedLeague, selectLeague, isLoading, error } = useLeagueSelection();

  return (
    <div className="app">
      <header className="app-header">
        <h1 className="app-title">PoE Flip Finder</h1>
        <LeagueSelector
          leagues={leagues}
          selectedLeague={selectedLeague}
          onSelect={selectLeague}
          isLoading={isLoading}
          error={error}
        />
      </header>
      <main className="app-main">
        {selectedLeague ? (
          <p>Showing flips for {selectedLeague.name}.</p>
        ) : (
          <p>Select a league to get started.</p>
        )}
      </main>
    </div>
  );
}

export default App;
