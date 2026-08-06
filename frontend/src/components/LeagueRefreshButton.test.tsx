import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { LeagueRefreshButton } from './LeagueRefreshButton';

describe('LeagueRefreshButton', () => {
  it('calls onRefresh when clicked', async () => {
    const onRefresh = vi.fn();
    render(<LeagueRefreshButton onRefresh={onRefresh} isRefreshing={false} />);

    await userEvent.click(screen.getByRole('button', { name: 'Refresh leagues' }));

    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it('disables the button while refreshing', () => {
    render(<LeagueRefreshButton onRefresh={vi.fn()} isRefreshing />);

    expect(screen.getByRole('button', { name: 'Refresh leagues' })).toBeDisabled();
  });
});
