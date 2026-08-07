import { BuildInfoBar } from './components/BuildInfoBar';
import { DataFreshnessStamp } from './components/DataFreshnessStamp';
import { FlipOpportunityTable } from './components/FlipOpportunityTable';
import { FlipTechniqueFilterBar } from './components/FlipTechniqueFilterBar';
import { IngestionRefreshButton } from './components/IngestionRefreshButton';
import { LeagueRefreshButton } from './components/LeagueRefreshButton';
import { LeagueSelector } from './components/LeagueSelector';
import { useFavoriteRoutes } from './hooks/useFavoriteRoutes';
import { useFlipOpportunities } from './hooks/useFlipOpportunities';
import { useIngestionFreshness } from './hooks/useIngestionFreshness';
import { useLeagueSelection } from './hooks/useLeagueSelection';
import { useSortAndThresholds } from './hooks/useSortAndThresholds';
import { useTechniqueFilters } from './hooks/useTechniqueFilters';
import { buildDisplayGroups, getRouteKey } from './presenters/flipOpportunityTablePresenter';

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
  const {
    opportunities,
    isLoading: isOpportunitiesLoading,
    error: opportunitiesError,
  } = useFlipOpportunities(selectedLeague?.id ?? null);
  const { enabledTechniques, toggleTechnique } = useTechniqueFilters();
  const { sortColumn, sortDirection, toggleSort, thresholds, setThreshold } = useSortAndThresholds();
  const { favoriteRouteKeys, toggleFavorite } = useFavoriteRoutes();

  const { favorites, others } = buildDisplayGroups(opportunities, {
    enabledTechniques,
    thresholds,
    sortColumn,
    sortDirection,
    favoriteRouteKeys,
  });

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
          <div className="panel">
            <FlipTechniqueFilterBar enabledTechniques={enabledTechniques} onToggle={toggleTechnique} />
            <FlipOpportunityTable
              favorites={favorites}
              others={others}
              isLoading={isOpportunitiesLoading}
              error={opportunitiesError}
              sortColumn={sortColumn}
              sortDirection={sortDirection}
              onSort={toggleSort}
              thresholds={thresholds}
              onThresholdChange={setThreshold}
              onToggleFavorite={(opportunity) => toggleFavorite(getRouteKey(opportunity))}
            />
          </div>
        ) : (
          <p>Select a league to get started.</p>
        )}
      </main>
      <BuildInfoBar />
    </div>
  );
}

export default App;
