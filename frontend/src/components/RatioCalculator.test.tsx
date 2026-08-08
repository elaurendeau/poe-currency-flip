import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { RatioCalculator } from './RatioCalculator';

const baseProps = {
  isOpen: false,
  onToggleOpen: vi.fn(),
  onClose: vi.fn(),
  ratioText: '',
  onRatioTextChange: vi.fn(),
  leftText: '',
  onLeftTextChange: vi.fn(),
  rightText: '',
  onRightTextChange: vi.fn(),
  isRatioValid: false,
  achievedRatio: null,
  isExactMatch: false,
  closestMatches: [],
  suggestions: [],
};

describe('RatioCalculator', () => {
  it('shows only the launcher button when closed', () => {
    render(<RatioCalculator {...baseProps} />);

    expect(screen.getByRole('button', { name: 'Open ratio calculator' })).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('calls onToggleOpen when the launcher is clicked', async () => {
    const onToggleOpen = vi.fn();
    render(<RatioCalculator {...baseProps} onToggleOpen={onToggleOpen} />);

    await userEvent.click(screen.getByRole('button', { name: 'Open ratio calculator' }));

    expect(onToggleOpen).toHaveBeenCalled();
  });

  it('renders the panel with the three fields when open', () => {
    render(
      <RatioCalculator
        {...baseProps}
        isOpen
        ratioText="15.5:1"
        leftText="31"
        rightText="2"
        isRatioValid
        achievedRatio="15.5"
        isExactMatch
      />,
    );

    expect(screen.getByRole('dialog', { name: 'Ratio calculator' })).toBeInTheDocument();
    expect(screen.getByLabelText('Ratio')).toHaveValue('15.5:1');
    expect(screen.getByLabelText('Left')).toHaveValue('31');
    expect(screen.getByLabelText('Right')).toHaveValue('2');
    expect(screen.getByText(/exact match/)).toBeInTheDocument();
  });

  it('disables left/right and shows an error when the ratio is invalid', () => {
    render(<RatioCalculator {...baseProps} isOpen ratioText="nonsense" />);

    expect(screen.getByLabelText('Left')).toBeDisabled();
    expect(screen.getByLabelText('Right')).toBeDisabled();
    expect(screen.getByText('Enter a ratio like 15.5:1')).toBeInTheDocument();
  });

  it('renders both closest matches and the whole-ratio suggestions when the match is not exact', () => {
    render(
      <RatioCalculator
        {...baseProps}
        isOpen
        ratioText="15.5:1"
        leftText="109"
        rightText="7"
        isRatioValid
        achievedRatio="15.57"
        isExactMatch={false}
        closestMatches={[
          { left: 108, right: 7, achievedRatio: '15.43' },
          { left: 109, right: 7, achievedRatio: '15.57' },
        ]}
        suggestions={[
          { ratio: 16, left: 112, right: 7 },
          { ratio: 15, left: 105, right: 7 },
        ]}
      />,
    );

    expect(screen.getByText('Closest matches')).toBeInTheDocument();
    expect(screen.getByText('≈15.43:1')).toBeInTheDocument();
    expect(screen.getByText('108:7')).toBeInTheDocument();
    expect(screen.getByText('≈15.57:1')).toBeInTheDocument();
    expect(screen.getByText('109:7')).toBeInTheDocument();

    expect(screen.getByText('Other whole-ratio options')).toBeInTheDocument();
    expect(screen.getByText('16:1')).toBeInTheDocument();
    expect(screen.getByText('112:7')).toBeInTheDocument();
    expect(screen.getByText('15:1')).toBeInTheDocument();
    expect(screen.getByText('105:7')).toBeInTheDocument();

    // The exact-match single-line hint must not also render alongside these.
    expect(screen.queryByText(/exact match/)).not.toBeInTheDocument();
  });

  it('calls onClose when the close button is clicked', async () => {
    const onClose = vi.fn();
    render(<RatioCalculator {...baseProps} isOpen onClose={onClose} />);

    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalled();
  });
});
