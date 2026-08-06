import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { FlipOpportunity } from '../entities/FlipOpportunity';
import { FlipOpportunityTable } from './FlipOpportunityTable';

const opportunity: FlipOpportunity = {
  technique: 'EXCHANGE_SPREAD',
  start: [{ currencyId: 'A', name: 'Chaos Orb', iconUrl: null, quantity: 1 }],
  via: [{ currencyId: 'B', name: 'Scroll of Wisdom', iconUrl: null, quantity: 366 }],
  sell: [{ currencyId: 'A', name: 'Chaos Orb', iconUrl: null, quantity: 1.9784 }],
  marginPercent: 97.84,
  profit: 0.9784,
  volume: 1234,
  detail: 'instant 185:1 · competitive 366:1',
};

describe('FlipOpportunityTable', () => {
  it('shows a loading state', () => {
    render(<FlipOpportunityTable opportunities={[]} isLoading error={null} />);

    expect(screen.getByText(/loading flip opportunities/i)).toBeInTheDocument();
  });

  it('shows an error state', () => {
    render(<FlipOpportunityTable opportunities={[]} isLoading={false} error={new Error('boom')} />);

    expect(screen.getByText(/failed to load flip opportunities/i)).toBeInTheDocument();
  });

  it('shows an empty state when there are no opportunities', () => {
    render(<FlipOpportunityTable opportunities={[]} isLoading={false} error={null} />);

    expect(screen.getByText(/no flip opportunities yet/i)).toBeInTheDocument();
  });

  it('renders one row per opportunity with formatted values', () => {
    render(<FlipOpportunityTable opportunities={[opportunity]} isLoading={false} error={null} />);

    expect(screen.getAllByText('Chaos Orb')).toHaveLength(2); // start and sell
    expect(screen.getByText('Scroll of Wisdom')).toBeInTheDocument();
    expect(screen.getByText('366')).toBeInTheDocument();
    expect(screen.getByText('≈1.98')).toBeInTheDocument();
    expect(screen.getByText('+98%')).toBeInTheDocument();
    expect(screen.getByText('+0.98')).toBeInTheDocument();
    expect(screen.getByText('1.2k')).toBeInTheDocument();
    expect(screen.getByText('instant 185:1 · competitive 366:1')).toBeInTheDocument();
  });

  it('renders multiple rows for multiple opportunities', () => {
    const second: FlipOpportunity = { ...opportunity, via: [{ ...opportunity.via[0], name: 'Portal Scroll' }] };
    render(<FlipOpportunityTable opportunities={[opportunity, second]} isLoading={false} error={null} />);

    expect(screen.getByText('Scroll of Wisdom')).toBeInTheDocument();
    expect(screen.getByText('Portal Scroll')).toBeInTheDocument();
  });
});
