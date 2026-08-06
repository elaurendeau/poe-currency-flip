import { DataFreshnessStamp } from './components/DataFreshnessStamp';
import { IngestionRefreshButton } from './components/IngestionRefreshButton';
import { LeagueRefreshButton } from './components/LeagueRefreshButton';
import { LeagueSelector } from './components/LeagueSelector';
import { useIngestionFreshness } from './hooks/useIngestionFreshness';
import { useLeagueSelection } from './hooks/useLeagueSelection';

function App() {
  const { leagues, selectedLeague, selectLeague, isLoading, isRefreshing, error, refresh } =
    useLeagueSelection();
  const {
    freshness,
    isLoading: isFreshnessLoading,
    isRefreshing: isIngestionRefreshing,
    error: freshnessError,
    lastRefreshResult,
    refresh: refreshIngestion,
  } = useIngestionFreshness();

  return (
    <div className="app">
      <header className="app-header">
        <h1 className="app-title">PoE Flip Finder</h1>
        <DataFreshnessStamp
          freshness={freshness}
          isLoading={isFreshnessLoading}
          error={freshnessError}
          lastRefreshResult={lastRefreshResult}
        />
        <div className="league-controls">
          <span className="data-label">Data</span>
          <IngestionRefreshButton onRefresh={refreshIngestion} isRefreshing={isIngestionRefreshing} />
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
