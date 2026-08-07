import { API_BASE_URL } from '../config/env';
import type { League } from '../entities/League';
import type { components } from './generated/schema';

type LeagueDto = components['schemas']['League'];

export class LeagueApiError extends Error {}

function toLeague(dto: LeagueDto): League {
  return { id: dto.id, name: dto.name, isDefault: dto.isDefault };
}

export async function fetchLeagues(): Promise<League[]> {
  const response = await fetch(`${API_BASE_URL}/leagues`);
  if (!response.ok) {
    throw new LeagueApiError(`GET /leagues failed with status ${response.status}`);
  }
  const dtos: LeagueDto[] = await response.json();
  return dtos.map(toLeague);
}

// The only call that hits GGG's live Leagues API -- fetchLeagues() above is
// a cached DB read. Triggered only by the user's explicit "Refresh leagues"
// action (docs/PRD.md § 7.7).
export async function refreshLeagues(): Promise<League[]> {
  const response = await fetch(`${API_BASE_URL}/leagues/refresh`, { method: 'POST' });
  if (!response.ok) {
    throw new LeagueApiError(`POST /leagues/refresh failed with status ${response.status}`);
  }
  const dtos: LeagueDto[] = await response.json();
  return dtos.map(toLeague);
}
