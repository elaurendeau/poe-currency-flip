import type { CurrencyAmount, FlipOpportunity } from '../entities/FlipOpportunity';
import { formatMargin, formatProfit, formatQuantity, formatVolume } from '../presenters/flipOpportunityPresenter';

interface FlipOpportunityTableProps {
  opportunities: FlipOpportunity[];
  isLoading: boolean;
  error: Error | null;
}

export function FlipOpportunityTable({ opportunities, isLoading, error }: FlipOpportunityTableProps) {
  if (error) {
    return <p className="flip-table-message flip-table-message--error">Failed to load flip opportunities</p>;
  }

  if (isLoading) {
    return <p className="flip-table-message">Loading flip opportunities…</p>;
  }

  if (opportunities.length === 0) {
    return <p className="flip-table-message">No flip opportunities yet.</p>;
  }

  return (
    <>
      <div className="grid header-row">
        <span style={{ textAlign: 'center' }}>Start</span>
        <span>Via</span>
        <span style={{ textAlign: 'center' }}>Sell</span>
        <span style={{ textAlign: 'right' }}>Margin</span>
        <span style={{ textAlign: 'right' }}>Profit</span>
        <span style={{ textAlign: 'right' }}>Volume</span>
      </div>
      {opportunities.map((opportunity, index) => (
        // eslint-disable-next-line react/no-array-index-key -- opportunities carry no stable id yet (never persisted, computed fresh every refresh)
        <FlipOpportunityRow key={index} opportunity={opportunity} />
      ))}
    </>
  );
}

function FlipOpportunityRow({ opportunity }: { opportunity: FlipOpportunity }) {
  const margin = formatMargin(opportunity.marginPercent);
  const profit = formatProfit(opportunity.profit, opportunity.marginPercent);

  return (
    <div className="grid row">
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
