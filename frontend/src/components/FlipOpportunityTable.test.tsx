import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { FlipOpportunity } from '../entities/FlipOpportunity';
import { FlipOpportunityTable } from './FlipOpportunityTable';

const opportunity: FlipOpportunity = {
  technique: 'EXCHANGE_SPREAD',
  start: [{ currencyId: 'A', name: 'Chaos Orb', iconUrl: null, itemType: 'CURRENCY', quantity: 1 }],
  via: [{ currencyId: 'B', name: 'Scroll of Wisdom', iconUrl: null, itemType: 'CURRENCY', quantity: 366 }],
  sell: [{ currencyId: 'A', name: 'Chaos Orb', iconUrl: null, itemType: 'CURRENCY', quantity: 1.9784 }],
  marginPercent: 97.84,
  profit: { currencyId: 'A', name: 'Chaos Orb', iconUrl: null, itemType: 'CURRENCY', quantity: 0.9784 },
  volume: 1234,
  detail: 'buy 365:1 · sell 186:1',
};

const second: FlipOpportunity = { ...opportunity, via: [{ ...opportunity.via[0], name: 'Portal Scroll' }] };

function baseProps() {
  return {
    favorites: [] as FlipOpportunity[],
    others: [] as FlipOpportunity[],
    isLoading: false,
    error: null,
    sortColumn: 'margin' as const,
    sortDirection: 'desc' as const,
    onSort: vi.fn(),
    thresholds: {},
    onThresholdChange: vi.fn(),
    onToggleFavorite: vi.fn(),
  };
}

describe('FlipOpportunityTable', () => {
  it('shows a loading state', () => {
    render(<FlipOpportunityTable {...baseProps()} isLoading />);

    expect(screen.getByText(/loading flip opportunities/i)).toBeInTheDocument();
  });

  it('shows an error state', () => {
    render(<FlipOpportunityTable {...baseProps()} error={new Error('boom')} />);

    expect(screen.getByText(/failed to load flip opportunities/i)).toBeInTheDocument();
  });

  it('shows an empty state when there are no opportunities in either group', () => {
    render(<FlipOpportunityTable {...baseProps()} />);

    expect(screen.getByText(/no flip opportunities yet/i)).toBeInTheDocument();
  });

  it('renders one row per opportunity with formatted values', () => {
    render(<FlipOpportunityTable {...baseProps()} others={[opportunity]} />);

    expect(screen.getAllByText('Chaos Orb')).toHaveLength(2); // start and sell
    expect(screen.getByText('Scroll of Wisdom')).toBeInTheDocument();
    expect(screen.getByText('366')).toBeInTheDocument();
    expect(screen.getByText('≈1.98')).toBeInTheDocument();
    expect(screen.getByText('+98%')).toBeInTheDocument();
    expect(screen.getByText('+0.98')).toBeInTheDocument();
    expect(screen.getByText('1.2k')).toBeInTheDocument();
    expect(screen.getByText('buy 365:1 · sell 186:1')).toBeInTheDocument();
  });

  it('renders multiple rows for multiple opportunities', () => {
    render(<FlipOpportunityTable {...baseProps()} others={[opportunity, second]} />);

    expect(screen.getByText('Scroll of Wisdom')).toBeInTheDocument();
    expect(screen.getByText('Portal Scroll')).toBeInTheDocument();
  });

  it('renders a generic card icon instead of an <img> for a divination card, which has no real icon', () => {
    const withCard: FlipOpportunity = {
      ...opportunity,
      via: [{ currencyId: 'C', name: 'The Doctor', iconUrl: null, itemType: 'DIVINATION_CARD', quantity: 5 }],
    };
    const { container } = render(<FlipOpportunityTable {...baseProps()} others={[withCard]} />);

    expect(screen.getByText('The Doctor')).toBeInTheDocument();
    expect(container.querySelector('.via-icons img')).not.toBeInTheDocument();
    expect(container.querySelector('.via-icons .divination-card-icon')).toBeInTheDocument();
  });

  it('renders every via step with an arrow between them, not just the first', () => {
    const divinationCard: FlipOpportunity = {
      ...opportunity,
      via: [
        { currencyId: 'C', name: 'The Vanity', iconUrl: null, itemType: 'DIVINATION_CARD', quantity: 5 },
        { currencyId: 'D', name: 'Regal Orb', iconUrl: null, itemType: 'CURRENCY', quantity: 1 },
      ],
    };
    const { container } = render(<FlipOpportunityTable {...baseProps()} others={[divinationCard]} />);

    // Both names are bare text nodes (matching the mockup's markup exactly),
    // so they're read via textContent rather than getByText -- getByText
    // only matches an element's direct text-node children, and here two
    // sibling names share the same parent.
    expect(container.querySelector('.via-icons')?.textContent).toContain('The Vanity');
    expect(container.querySelector('.via-icons')?.textContent).toContain('Regal Orb');
    expect(container.querySelectorAll('.via-icons .arrow')).toHaveLength(1);
  });

  it('renders favorites above others with a visible divider between the groups', () => {
    render(<FlipOpportunityTable {...baseProps()} favorites={[opportunity]} others={[second]} />);

    const rows = screen.getAllByTestId(/^flip-row-/);
    expect(rows).toHaveLength(2);
    expect(screen.getByTestId('favorites-divider')).toBeInTheDocument();
  });

  it('does not render a divider when there are no favorites', () => {
    render(<FlipOpportunityTable {...baseProps()} others={[opportunity]} />);

    expect(screen.queryByTestId('favorites-divider')).not.toBeInTheDocument();
  });

  it('marks the active sort column and calls onSort when a column header is clicked', () => {
    const onSort = vi.fn();
    render(<FlipOpportunityTable {...baseProps()} onSort={onSort} sortColumn="volume" sortDirection="asc" />);

    expect(screen.getByText('Volume').closest('.col-label')).toHaveClass('active');

    fireEvent.click(screen.getByText('Profit'));

    expect(onSort).toHaveBeenCalledWith('profit');
  });

  it('calls onThresholdChange with a parsed number when a threshold input changes', () => {
    const onThresholdChange = vi.fn();
    render(<FlipOpportunityTable {...baseProps()} onThresholdChange={onThresholdChange} />);

    fireEvent.change(screen.getByPlaceholderText('min'), { target: { value: '50' } });

    expect(onThresholdChange).toHaveBeenCalledWith('volume', 50);
  });

  it('calls onThresholdChange with null when a threshold input is cleared', () => {
    const onThresholdChange = vi.fn();
    render(
      <FlipOpportunityTable {...baseProps()} onThresholdChange={onThresholdChange} thresholds={{ volume: 50 }} />,
    );

    fireEvent.change(screen.getByPlaceholderText('min'), { target: { value: '' } });

    expect(onThresholdChange).toHaveBeenCalledWith('volume', null);
  });

  it('right-clicking a non-favorited row opens a context menu offering to favorite it', () => {
    render(<FlipOpportunityTable {...baseProps()} others={[opportunity]} />);

    fireEvent.contextMenu(screen.getByTestId('flip-row-0'));

    expect(screen.getByText('Favorite')).toBeInTheDocument();
  });

  it('right-clicking a favorited row opens a context menu offering to unfavorite it', () => {
    render(<FlipOpportunityTable {...baseProps()} favorites={[opportunity]} />);

    fireEvent.contextMenu(screen.getByTestId('flip-row-0'));

    expect(screen.getByText('Unfavorite')).toBeInTheDocument();
  });

  it('calls onToggleFavorite with the opportunity when the context menu item is clicked', () => {
    const onToggleFavorite = vi.fn();
    render(<FlipOpportunityTable {...baseProps()} others={[opportunity]} onToggleFavorite={onToggleFavorite} />);

    fireEvent.contextMenu(screen.getByTestId('flip-row-0'));
    fireEvent.click(screen.getByText('Favorite'));

    expect(onToggleFavorite).toHaveBeenCalledWith(opportunity);
  });
});
