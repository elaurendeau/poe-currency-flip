# Data Sources

**Related docs:** [PRD.md](PRD.md) (what we're building) · [ARCHITECTURE.md](ARCHITECTURE.md) (how we isolate ourselves from these sources) · [TECH_STACK.md](TECH_STACK.md) (technology decisions)

This is the contract reference for every external data source the app depends on. **This is the first file to check — and update — when GGG or the PoE Wiki changes shape or behavior.** Each entry lists what's verified, when, and how. See [ARCHITECTURE.md](ARCHITECTURE.md) for how these facts translate into adapters, validation, and contract tests.

## Currency Exchange Data

**Endpoint:** `GET https://web.poecdn.com/api/currency-exchange[/<realm>][/<id>]`
**Auth:** None required.
**Last verified:** 2026-08-05, by direct testing.

Verified facts:

- **Public, no authentication.** No POESESSID, no login, no OAuth. Officially documented in GGG's developer API reference — sanctioned third-party use, not a scrape of an authenticated page.
- **Sequential change-stream, not a query-by-current-state API.** Each call returns one hour of market activity plus a `next_change_id` pointing at the next hour. Calling with an arbitrary/future `id` (e.g. jumping straight to "now") returns **HTTP 404** — confirmed empirically. The only way to reach current data is to walk the chain forward hour-by-hour from a stored checkpoint (same pattern as GGG's Public Stash Tab river). Calling with no `id` starts at the very first hour of Currency Exchange history (~mid-2024; first observed `next_change_id`: `1722027600`, i.e. 2024-07-26).
- **Data shape is hourly aggregates of executed trades, not a live order book.** Each market entry (a currency/currency or currency/divination-card pair) reports, per hour: `league`, `market_id`, `market_pair` (two internal item IDs), `volume_traded`, `lowest_stock`/`highest_stock`, and `lowest_ratio`/`highest_ratio` (the range of rates that actually filled that hour, keyed per side of the pair).
  - Verified example: `Metadata/Items/Currency/CurrencyPortal` ↔ `Metadata/Items/Currency/CurrencyIdentification` (Portal Scroll ↔ Scroll of Wisdom) showed `lowest_ratio` of 1:5 and `highest_ratio` of 1:1 within a single hour — a real, meaningful spread, but a historical range rather than a live "instant vs. competitive" snapshot like pressing Alt in-game shows.
- **Divination cards are included** as one side of a market pair. Verified: `Metadata/Items/DivinationCards/DivinationCardVanity` traded against `Metadata/Items/Currency/CurrencyRerollRare` appears as a normal market entry.
- **`realm` parameter** accepts `xbox`, `sony`, or `poe2`; omitted = PoE1 PC (our target).
- **No rate limiting observed** in a burst of 5 sequential requests (~700–900ms apart, all HTTP 200). This is CDN-hosted (`web.poecdn.com`), distinct from the live trade-search endpoints on `pathofexile.com` which do carry documented, stricter rate limits (see below) — those do not apply to this endpoint.
- Response size grows with league activity — observed ~300–500KB per hour early in a league. Full historical backfill from launch would be several GB; not needed since the product only cares about current state (see [ARCHITECTURE.md](ARCHITECTURE.md) ingestion model).

**Known limitation:** true live order-book depth (the in-game Alt-click "competitive rate" view) is **not exposed**. `lowest_ratio`/`highest_ratio` per hour is the closest available proxy. This directly scopes [PRD.md Feature B](PRD.md#72-feature-b--exchange-spreadmargin-finder).

## League List

**Endpoint:** `GET https://api.pathofexile.com/leagues`
**Auth:** None required.
**Last verified:** 2026-08-05, by direct testing.

Verified facts:

- **Public, no authentication.** Returned 16 active leagues at time of testing.
- Fields present: `id`, `name`, `realm`, `url`, `startAt`, `endAt`, `description`, `category` (`{ id, current? }`), `registerAt`, `delveEvent`, `rules` (array of `{ id, name, description }`).
- **Current challenge league** is identifiable via `category.current: true`. Verified: "Allflame" (`startAt: 2026-07-24T20:00:00Z`) carries `category: { id: "Allflame", current: true }`, as do its hardcore/ruthless/SSF variants (same category, `current: true`).
- **Solo Self-Found leagues are identifiable via `rules`**: any league with a rule `{ id: "NoParties" }` is SSF (no trading, no Currency Exchange access). Verified present on "Solo Self-Found", "SSF Allflame", "HC SSF Allflame", "SSF R Allflame", "HC SSF R Allflame".
- Other rule ids observed: `Hardcore` (hardcore ruleset), `HardMode` (Ruthless ruleset). These do **not** by themselves indicate no-trade status.
- Non-SSF leagues confirmed present in the current lineup: `Standard`, `Hardcore`, `Ruthless`, `Hardcore Ruthless`, plus current-league equivalents `Allflame`, `Hardcore Allflame`, `Ruthless Allflame`, `HC Ruthless Allflame`. These should still be cross-checked against actual Currency Exchange activity per the league resolution algorithm in [ARCHITECTURE.md](ARCHITECTURE.md#league-resolution), since rule-based filtering alone is not guaranteed to catch every no-Exchange case.

## Vendor Sell Rates & Recipes

**Source:** [PoE Wiki — Currency](https://www.poewiki.net/wiki/Currency) and item-specific pages (e.g. [Scroll of Wisdom](https://www.poewiki.net/wiki/Scroll_of_Wisdom)).
**Auth:** None (public wiki).
**Last verified:** Not yet — source identified, not yet scraped/captured as reference data.

Notes:

- No API; this is static, low-volatility game data (vendor recipes change rarely, only on game updates).
- Needs a one-time capture into our own reference data (see [ARCHITECTURE.md § Centralized Reference Data](ARCHITECTURE.md#4-centralized-reference-data)), refreshed manually if GGG changes a recipe.

## Divination Card Turn-In Rewards

**Source:** [PoE Wiki](https://www.poewiki.net/wiki/Divination_card) (divination card pages/category).
**Auth:** None (public wiki).
**Last verified:** Not yet — source identified, not yet scraped/captured or classified.

Notes:

- No API; static game data.
- Requires a one-time classification pass: fixed/predictable currency reward (in scope per [PRD.md § 7.3](PRD.md#73-feature-c--divination-card-flip-finder)) vs. gamble/random-item reward (excluded).

## Trade Search API (for context — not used)

GGG's live trade-search endpoints (`pathofexile.com/api/trade/...`) carry documented, stricter per-IP rate limits (e.g., ~5 requests/12s for search, ~5/17s for exchange search), and the interactive trade *site* increasingly requires authentication. We deliberately do not depend on these — the CDN-hosted `currency-exchange` river above and the public `leagues` endpoint cover everything the product needs without touching this more fragile, rate-limited surface.
