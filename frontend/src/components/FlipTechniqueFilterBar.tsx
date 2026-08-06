import type { ReactElement } from 'react';
import type { Technique } from '../entities/FlipOpportunity';
import { ALL_TECHNIQUES } from '../entities/FlipOpportunity';

interface FlipTechniqueFilterBarProps {
  enabledTechniques: Record<Technique, boolean>;
  onToggle: (technique: Technique) => void;
}

const TECHNIQUE_LABELS: Record<Technique, string> = {
  VENDOR_RECIPE: 'Vendor recipe',
  EXCHANGE_SPREAD: 'Exchange spread',
  DIVINATION_CARD: 'Divination card',
  BULK_BUY: 'Bulk buy',
};

const TECHNIQUE_ICONS: Record<Technique, ReactElement> = {
  VENDOR_RECIPE: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21v-1a7 7 0 0 1 14 0v1" />
    </svg>
  ),
  EXCHANGE_SPREAD: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M4 12h7M8 8l-4 4 4 4" />
      <path d="M20 12h-7M16 8l4 4-4 4" />
    </svg>
  ),
  DIVINATION_CARD: (
    <svg viewBox="0 0 24 24" fill="none" stroke="#c98ded" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="4" y="6" width="12" height="16" rx="2" transform="rotate(-8 10 14)" />
      <rect x="9" y="4" width="12" height="16" rx="2" transform="rotate(8 15 12)" />
    </svg>
  ),
  BULK_BUY: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M3 9l9-5 9 5-9 5-9-5z" />
      <path d="M3 9v6l9 5 9-5V9" />
      <path d="M12 14v6" />
    </svg>
  ),
};

export function FlipTechniqueFilterBar({ enabledTechniques, onToggle }: FlipTechniqueFilterBarProps) {
  return (
    <div className="filter-bar">
      {ALL_TECHNIQUES.map((technique) => (
        <label key={technique} className="filter-check">
          <input
            type="checkbox"
            checked={enabledTechniques[technique]}
            onChange={() => onToggle(technique)}
            aria-label={TECHNIQUE_LABELS[technique]}
          />
          {TECHNIQUE_ICONS[technique]}
          {TECHNIQUE_LABELS[technique]}
        </label>
      ))}
    </div>
  );
}
