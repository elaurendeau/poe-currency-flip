import type { MouseEvent as ReactMouseEvent } from 'react';
import type { CurrencyAmount, FlipOpportunity } from '../entities/FlipOpportunity';
import { useRowContextMenu } from '../hooks/useRowContextMenu';
import { formatMargin, formatProfit, formatQuantity, formatVolume } from '../presenters/flipOpportunityPresenter';
import type { SortColumn, SortDirection, ThresholdValues } from '../presenters/flipOpportunityTablePresenter';

interface FlipOpportunityTableProps {
  favorites: FlipOpportunity[];
  others: FlipOpportunity[];
  isLoading: boolean;
  error: Error | null;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  onSort: (column: SortColumn) => void;
  thresholds: ThresholdValues;
  onThresholdChange: (column: SortColumn, value: number | null) => void;
  onToggleFavorite: (opportunity: FlipOpportunity) => void;
}

interface ContextMenuPayload {
  opportunity: FlipOpportunity;
  isFavorite: boolean;
}

export function FlipOpportunityTable({
  favorites,
  others,
  isLoading,
  error,
  sortColumn,
  sortDirection,
  onSort,
  thresholds,
  onThresholdChange,
  onToggleFavorite,
}: FlipOpportunityTableProps) {
  const { menu, openMenu, closeMenu } = useRowContextMenu<ContextMenuPayload>();

  if (error) {
    return <p className="flip-table-message flip-table-message--error">Failed to load flip opportunities</p>;
  }

  if (isLoading) {
    return <p className="flip-table-message">Loading flip opportunities…</p>;
  }

  const isEmpty = favorites.length === 0 && others.length === 0;

  const handleMenuItemClick = () => {
    if (menu) onToggleFavorite(menu.payload.opportunity);
    closeMenu();
  };

  return (
    <>
      <div className="grid header-row">
        <span style={{ textAlign: 'center' }}>Start</span>
        <span>Via</span>
        <span style={{ textAlign: 'center' }}>Sell</span>
        <SortableColumnHeader
          column="margin"
          label="Margin"
          placeholder="min %"
          sortColumn={sortColumn}
          sortDirection={sortDirection}
          onSort={onSort}
          thresholdValue={thresholds.margin}
          onThresholdChange={onThresholdChange}
        />
        <SortableColumnHeader
          column="profit"
          label="Profit"
          placeholder="min c"
          sortColumn={sortColumn}
          sortDirection={sortDirection}
          onSort={onSort}
          thresholdValue={thresholds.profit}
          onThresholdChange={onThresholdChange}
        />
        <SortableColumnHeader
          column="volume"
          label="Volume"
          placeholder="min"
          sortColumn={sortColumn}
          sortDirection={sortDirection}
          onSort={onSort}
          thresholdValue={thresholds.volume}
          onThresholdChange={onThresholdChange}
        />
      </div>
      {isEmpty && <p className="flip-table-message">No flip opportunities yet.</p>}
      {favorites.map((opportunity, index) => (
        <FlipOpportunityRow
          // eslint-disable-next-line react/no-array-index-key -- opportunities carry no stable id yet (never persisted, computed fresh every refresh)
          key={index}
          testId={`flip-row-${index}`}
          opportunity={opportunity}
          isFavorite
          onContextMenu={(event) => openMenu(event, { opportunity, isFavorite: true })}
        />
      ))}
      {favorites.length > 0 && others.length > 0 && (
        <div className="favorites-divider" data-testid="favorites-divider" />
      )}
      {others.map((opportunity, index) => (
        <FlipOpportunityRow
          // eslint-disable-next-line react/no-array-index-key -- opportunities carry no stable id yet (never persisted, computed fresh every refresh)
          key={index}
          testId={`flip-row-${favorites.length + index}`}
          opportunity={opportunity}
          isFavorite={false}
          onContextMenu={(event) => openMenu(event, { opportunity, isFavorite: false })}
        />
      ))}
      {menu && (
        <div className="ctx-menu" style={{ display: 'block', left: menu.x, top: menu.y }}>
          <div className="ctx-item" onClick={handleMenuItemClick}>
            <StarIcon />
            {menu.payload.isFavorite ? 'Unfavorite' : 'Favorite'}
          </div>
        </div>
      )}
    </>
  );
}

interface SortableColumnHeaderProps {
  column: SortColumn;
  label: string;
  placeholder: string;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  onSort: (column: SortColumn) => void;
  thresholdValue: number | undefined;
  onThresholdChange: (column: SortColumn, value: number | null) => void;
}

function SortableColumnHeader({
  column,
  label,
  placeholder,
  sortColumn,
  sortDirection,
  onSort,
  thresholdValue,
  onThresholdChange,
}: SortableColumnHeaderProps) {
  const isActive = sortColumn === column;

  return (
    <div className="col-head">
      <span className={`col-label${isActive ? ' active' : ''}`} onClick={() => onSort(column)}>
        {label} <SortArrowIcon direction={isActive ? sortDirection : null} />
      </span>
      <input
        className="col-filter"
        type="number"
        placeholder={placeholder}
        value={thresholdValue ?? ''}
        onChange={(event) => {
          const raw = event.target.value;
          onThresholdChange(column, raw === '' ? null : Number(raw));
        }}
      />
    </div>
  );
}

function FlipOpportunityRow({
  opportunity,
  isFavorite,
  onContextMenu,
  testId,
}: {
  opportunity: FlipOpportunity;
  isFavorite: boolean;
  onContextMenu: (event: ReactMouseEvent) => void;
  testId: string;
}) {
  const margin = formatMargin(opportunity.marginPercent);
  const profit = formatProfit(opportunity.profit, opportunity.marginPercent);

  return (
    <div
      className={`grid row${isFavorite ? ' fav' : ''}`}
      data-testid={testId}
      onContextMenu={(event) => {
        event.preventDefault();
        onContextMenu(event);
      }}
    >
      {isFavorite && (
        <span className="fav-star" aria-hidden="true">
          <StarIcon />
        </span>
      )}
      <CurrencyCell amount={opportunity.start[0]} />
      <div>
        <div className="via-icons">
          <span className="qty">{formatQuantity(opportunity.via[0].quantity)}</span>
          {opportunity.via[0].iconUrl && <img src={opportunity.via[0].iconUrl} alt="" />}
          {opportunity.via[0].name}
        </div>
        <div className="sub">{opportunity.detail}</div>
      </div>
      <CurrencyCell amount={opportunity.sell[0]} />
      <div className={`margin ${margin.colorClass}`}>{margin.text}</div>
      <div className={`profit ${profit.colorClass}`}>
        {profit.text}
        {opportunity.sell[0].iconUrl && <img src={opportunity.sell[0].iconUrl} alt="" />}
      </div>
      <div className="vol">{formatVolume(opportunity.volume)}</div>
    </div>
  );
}

function CurrencyCell({ amount }: { amount: CurrencyAmount }) {
  return (
    <div className="cur">
      <div className="cur-top">
        <span className="qty">{formatQuantity(amount.quantity)}</span>
        {amount.iconUrl && <img src={amount.iconUrl} alt="" />}
      </div>
      {amount.name}
    </div>
  );
}

function SortArrowIcon({ direction }: { direction: SortDirection | null }) {
  if (direction === 'asc') {
    return (
      <svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M12 19V5M5 12l7-7 7 7" />
      </svg>
    );
  }
  if (direction === 'desc') {
    return (
      <svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M12 5v14M5 12l7 7 7-7" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M8 9l4-4 4 4M8 15l4 4 4-4" />
    </svg>
  );
}

function StarIcon() {
  return (
    <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor" aria-hidden="true">
      <path d="M12 2l2.9 6.6 7.1.6-5.4 4.7 1.6 7-6.2-3.8L5.8 21l1.6-7L2 9.2l7.1-.6z" />
    </svg>
  );
}
