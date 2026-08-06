import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import type { League } from '../entities/League';
import { LeagueSelector } from './LeagueSelector';

const leagues: League[] = [
  { id: 'Standard', name: 'Standard', isDefault: false },
  { id: 'Allflame', name: 'Allflame', isDefault: true },
];

describe('LeagueSelector', () => {
  it('renders an option per league with the selected league chosen', () => {
    render(
      <LeagueSelector
        leagues={leagues}
        selectedLeague={leagues[1]}
        onSelect={vi.fn()}
        isLoading={false}
        error={null}
      />,
    );

    expect(screen.getByRole('combobox', { name: 'League' })).toHaveValue('Allflame');
    expect(screen.getByRole('option', { name: 'Standard' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Allflame' })).toBeInTheDocument();
  });

  it('calls onSelect with the chosen league id', async () => {
    const onSelect = vi.fn();
    render(
      <LeagueSelector
        leagues={leagues}
        selectedLeague={leagues[1]}
        onSelect={onSelect}
        isLoading={false}
        error={null}
      />,
    );

    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'League' }), 'Standard');

    expect(onSelect).toHaveBeenCalledWith('Standard');
  });

  it('shows a loading state instead of the dropdown', () => {
    render(
      <LeagueSelector
        leagues={[]}
        selectedLeague={null}
        onSelect={vi.fn()}
        isLoading
        error={null}
      />,
    );

    expect(screen.getByText('Loading leagues…')).toBeInTheDocument();
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
  });

  it('shows an error state instead of the dropdown', () => {
    render(
      <LeagueSelector
        leagues={[]}
        selectedLeague={null}
        onSelect={vi.fn()}
        isLoading={false}
        error={new Error('boom')}
      />,
    );

    expect(screen.getByText('Failed to load leagues')).toBeInTheDocument();
  });
});
