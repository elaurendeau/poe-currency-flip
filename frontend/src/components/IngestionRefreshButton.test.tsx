import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { IngestionRefreshButton } from './IngestionRefreshButton';

describe('IngestionRefreshButton', () => {
  it('calls onRefresh when clicked', async () => {
    const onRefresh = vi.fn();
    render(<IngestionRefreshButton onRefresh={onRefresh} isRefreshing={false} />);

    await userEvent.click(screen.getByRole('button', { name: 'Refresh market data' }));

    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it('disables the button while refreshing', () => {
    render(<IngestionRefreshButton onRefresh={vi.fn()} isRefreshing />);

    expect(screen.getByRole('button', { name: 'Refresh market data' })).toBeDisabled();
  });
});
