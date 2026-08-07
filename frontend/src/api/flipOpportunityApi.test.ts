import { afterEach, describe, expect, it, vi } from 'vitest';
import flipOpportunitiesResponseFixture from './__fixtures__/flip-opportunities-response.json';
import { fetchFlipOpportunities, FlipOpportunityApiError } from './flipOpportunityApi';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('fetchFlipOpportunities', () => {
  it('normalizes a real FlipOpportunities API response into FlipOpportunity entities', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve(flipOpportunitiesResponseFixture),
    });
    vi.stubGlobal('fetch', fetchMock);

    const opportunities = await fetchFlipOpportunities('Standard');

    expect(opportunities).toHaveLength(2);
    const [opportunity] = opportunities;
    expect(opportunity.technique).toBe('EXCHANGE_SPREAD');
    expect(opportunity.start).toEqual([
      {
        currencyId: 'Metadata/Items/Currency/CurrencyRerollRare',
        name: 'Chaos Orb',
        iconUrl: 'https://www.pathofexile.com/gen/image/.../CurrencyRerollRare.png',
        itemType: 'CURRENCY',
        quantity: 1,
      },
    ]);
    expect(opportunity.via[0].quantity).toBe(366);
    expect(opportunity.sell[0].quantity).toBeCloseTo(1.9784);
    expect(opportunity.marginPercent).toBeCloseTo(97.84);
    expect(opportunity.profit.quantity).toBeCloseTo(0.9784);
    expect(opportunity.profit.currencyId).toBe('Metadata/Items/Currency/CurrencyRerollRare');
    expect(opportunity.volume).toBe(1234);
    expect(opportunity.detail).toBe('buy 365:1 · sell 186:1');

    // Bulk Buy is the first row shape where start and sell currencies
    // genuinely differ (not a round trip back to the same currency) --
    // regression coverage for that specifically, per docs/PRD.md § 7.5.
    const [, bulkBuy] = opportunities;
    expect(bulkBuy.technique).toBe('BULK_BUY');
    expect(bulkBuy.start[0].currencyId).toBe('Metadata/Items/Currency/CurrencyModValues');
    expect(bulkBuy.via[0].itemType).toBe('DIVINATION_CARD');
    expect(bulkBuy.via[0].iconUrl).toBeNull();
    expect(bulkBuy.sell[0].currencyId).toBe('Metadata/Items/Currency/CurrencyRerollRare');
    expect(bulkBuy.start[0].currencyId).not.toBe(bulkBuy.sell[0].currencyId);
  });

  it('url-encodes the league id and hits /flip-opportunities', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve([]),
    });
    vi.stubGlobal('fetch', fetchMock);

    await fetchFlipOpportunities('HC Ruthless Allflame');

    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringContaining('/flip-opportunities?league=HC%20Ruthless%20Allflame'),
    );
  });

  it('throws FlipOpportunityApiError when the response is not ok', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: false, status: 500, json: () => Promise.resolve([]) }),
    );

    await expect(fetchFlipOpportunities('Standard')).rejects.toBeInstanceOf(FlipOpportunityApiError);
  });
});
