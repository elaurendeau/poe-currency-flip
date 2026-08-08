import type { ClosestMatch, RatioSuggestion } from '../presenters/ratioCalculatorPresenter';

interface RatioCalculatorProps {
  isOpen: boolean;
  onToggleOpen: () => void;
  onClose: () => void;
  ratioText: string;
  onRatioTextChange: (value: string) => void;
  leftText: string;
  onLeftTextChange: (value: string) => void;
  rightText: string;
  onRightTextChange: (value: string) => void;
  isRatioValid: boolean;
  achievedRatio: string | null;
  isExactMatch: boolean;
  closestMatches: ClosestMatch[];
  suggestions: RatioSuggestion[];
}

export function RatioCalculator({
  isOpen,
  onToggleOpen,
  onClose,
  ratioText,
  onRatioTextChange,
  leftText,
  onLeftTextChange,
  rightText,
  onRightTextChange,
  isRatioValid,
  achievedRatio,
  isExactMatch,
  closestMatches,
  suggestions,
}: RatioCalculatorProps) {
  const showError = !isRatioValid && ratioText.trim() !== '';
  const showClosestMatches = isRatioValid && !isExactMatch && closestMatches.length > 0;
  const showSuggestions = isRatioValid && !isExactMatch && suggestions.length > 0;
  const ratioInputClassName = showError
    ? 'ratio-calculator-input ratio-calculator-input--error'
    : 'ratio-calculator-input';

  return (
    <>
      <button
        type="button"
        className="ratio-calculator-launcher"
        onClick={onToggleOpen}
        aria-label={isOpen ? 'Close ratio calculator' : 'Open ratio calculator'}
        title="Ratio calculator"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <rect x="4" y="2" width="16" height="20" rx="2" />
          <line x1="8" y1="6" x2="16" y2="6" />
          <line x1="8" y1="11" x2="8" y2="11.01" />
          <line x1="12" y1="11" x2="12" y2="11.01" />
          <line x1="16" y1="11" x2="16" y2="11.01" />
          <line x1="8" y1="15" x2="8" y2="15.01" />
          <line x1="12" y1="15" x2="12" y2="15.01" />
          <line x1="16" y1="15" x2="16" y2="15.01" />
          <line x1="8" y1="19" x2="16" y2="19" />
        </svg>
      </button>

      {isOpen && (
        <div className="ratio-calculator-bubble" role="dialog" aria-label="Ratio calculator">
          <div className="ratio-calculator-header">
            <span className="ratio-calculator-title">Ratio Calculator</span>
            <button type="button" className="ratio-calculator-close" onClick={onClose} aria-label="Close">
              ×
            </button>
          </div>
          <div className="ratio-calculator-body">
            <p className="ratio-calculator-help">
              Enter a ratio, then edit either number to find the closest whole-number match.
            </p>

            <label className="ratio-calculator-field">
              <span className="ratio-calculator-label">Ratio</span>
              <input
                className={ratioInputClassName}
                value={ratioText}
                onChange={(event) => onRatioTextChange(event.target.value)}
                placeholder="e.g. 15.5:1"
              />
            </label>

            <div className="ratio-calculator-pair-row">
              <label className="ratio-calculator-field">
                <span className="ratio-calculator-label">Left</span>
                <input
                  className="ratio-calculator-input"
                  value={leftText}
                  onChange={(event) => onLeftTextChange(event.target.value)}
                  disabled={!isRatioValid}
                />
              </label>
              <span className="ratio-calculator-sep">:</span>
              <label className="ratio-calculator-field">
                <span className="ratio-calculator-label">Right</span>
                <input
                  className="ratio-calculator-input"
                  value={rightText}
                  onChange={(event) => onRightTextChange(event.target.value)}
                  disabled={!isRatioValid}
                />
              </label>
            </div>

            {showError && <p className="ratio-calculator-error">Enter a ratio like 15.5:1</p>}

            {isRatioValid && isExactMatch && achievedRatio !== null && (
              <p className="ratio-calculator-hint">
                ≈ <span className="ratio-calculator-hint-value">{achievedRatio}</span>:1 — exact match
              </p>
            )}

            {showClosestMatches && (
              <div className="ratio-calculator-suggestions">
                <div className="ratio-calculator-suggestions-label">Closest matches</div>
                {closestMatches.map((match) => (
                  <div key={`${match.left}:${match.right}`} className="ratio-calculator-suggestion">
                    <span className="ratio-calculator-suggestion-ratio">≈{match.achievedRatio}:1</span>
                    <span className="ratio-calculator-suggestion-pair">
                      {match.left}:{match.right}
                    </span>
                  </div>
                ))}
              </div>
            )}

            {showSuggestions && (
              <div className="ratio-calculator-suggestions">
                <div className="ratio-calculator-suggestions-label">Other whole-ratio options</div>
                {suggestions.map((suggestion) => (
                  <div key={suggestion.ratio} className="ratio-calculator-suggestion">
                    <span className="ratio-calculator-suggestion-ratio">{suggestion.ratio}:1</span>
                    <span className="ratio-calculator-suggestion-pair">
                      {suggestion.left}:{suggestion.right}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}
