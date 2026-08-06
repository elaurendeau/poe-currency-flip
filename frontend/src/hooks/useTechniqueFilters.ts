import { useCallback, useState } from 'react';
import { ALL_TECHNIQUES, type Technique } from '../entities/FlipOpportunity';

export interface TechniqueFilters {
  enabledTechniques: Record<Technique, boolean>;
  toggleTechnique: (technique: Technique) => void;
}

function allEnabled(): Record<Technique, boolean> {
  return Object.fromEntries(ALL_TECHNIQUES.map((technique) => [technique, true])) as Record<Technique, boolean>;
}

export function useTechniqueFilters(): TechniqueFilters {
  const [enabledTechniques, setEnabledTechniques] = useState<Record<Technique, boolean>>(allEnabled);

  const toggleTechnique = useCallback((technique: Technique) => {
    setEnabledTechniques((current) => ({ ...current, [technique]: !current[technique] }));
  }, []);

  return { enabledTechniques, toggleTechnique };
}
