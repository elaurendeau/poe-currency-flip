import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { Technique } from '../entities/FlipOpportunity';
import { FlipTechniqueFilterBar } from './FlipTechniqueFilterBar';

const allEnabled: Record<Technique, boolean> = {
  VENDOR_RECIPE: true,
  EXCHANGE_SPREAD: true,
  DIVINATION_CARD: true,
  BULK_BUY: true,
};

describe('FlipTechniqueFilterBar', () => {
  it('renders one checked checkbox per technique', () => {
    render(<FlipTechniqueFilterBar enabledTechniques={allEnabled} onToggle={() => {}} />);

    expect(screen.getByLabelText('Vendor recipe')).toBeChecked();
    expect(screen.getByLabelText('Exchange spread')).toBeChecked();
    expect(screen.getByLabelText('Divination card')).toBeChecked();
    expect(screen.getByLabelText('Bulk buy')).toBeChecked();
  });

  it('reflects a disabled technique as unchecked', () => {
    render(<FlipTechniqueFilterBar enabledTechniques={{ ...allEnabled, BULK_BUY: false }} onToggle={() => {}} />);

    expect(screen.getByLabelText('Bulk buy')).not.toBeChecked();
  });

  it('calls onToggle with the technique when its checkbox is clicked', () => {
    const onToggle = vi.fn();
    render(<FlipTechniqueFilterBar enabledTechniques={allEnabled} onToggle={onToggle} />);

    fireEvent.click(screen.getByLabelText('Exchange spread'));

    expect(onToggle).toHaveBeenCalledWith('EXCHANGE_SPREAD');
  });
});
