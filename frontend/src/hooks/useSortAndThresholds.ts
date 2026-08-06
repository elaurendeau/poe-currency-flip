import { useCallback, useState } from 'react';
import type { SortColumn, SortDirection, ThresholdValues } from '../presenters/flipOpportunityTablePresenter';

export interface SortAndThresholds {
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  toggleSort: (column: SortColumn) => void;
  thresholds: ThresholdValues;
  setThreshold: (column: SortColumn, value: number | null) => void;
}

// Matches the mockup's default state: Margin column active, sorted descending.
const DEFAULT_SORT_COLUMN: SortColumn = 'margin';

export function useSortAndThresholds(): SortAndThresholds {
  const [sortColumn, setSortColumn] = useState<SortColumn>(DEFAULT_SORT_COLUMN);
  const [sortDirection, setSortDirection] = useState<SortDirection>('desc');
  const [thresholds, setThresholds] = useState<ThresholdValues>({});

  const toggleSort = useCallback((column: SortColumn) => {
    setSortColumn((currentColumn) => {
      if (currentColumn === column) {
        setSortDirection((currentDirection) => (currentDirection === 'desc' ? 'asc' : 'desc'));
        return currentColumn;
      }
      setSortDirection('desc');
      return column;
    });
  }, []);

  const setThreshold = useCallback((column: SortColumn, value: number | null) => {
    setThresholds((current) => {
      const next = { ...current };
      if (value === null) {
        delete next[column];
      } else {
        next[column] = value;
      }
      return next;
    });
  }, []);

  return { sortColumn, sortDirection, toggleSort, thresholds, setThreshold };
}
