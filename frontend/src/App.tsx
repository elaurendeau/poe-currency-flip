import { LeagueRefreshButton } from './components/LeagueRefreshButton';
import { LeagueSelector } from './components/LeagueSelector';
import { useLeagueSelection } from './hooks/useLeagueSelection';

function App() {
  const { leagues, selectedLeague, selectLeague, isLoading, isRefreshing, error, refresh } =
    useLeagueSelection();

  return (
    <div className="app">
      <header className="app-header">
        <h1 className="app-title">PoE Flip Finder</h1>
        <div className="league-controls">
          <LeagueSelector
            leagues={leagues}
            selectedLeague={selectedLeague}
            onSelect={selectLeague}
            isLoading={isLoading}
            error={error}
          />
          <LeagueRefreshButton onRefresh={refresh} isRefreshing={isRefreshing || isLoading} />
        </div>
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
