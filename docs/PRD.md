# PRD: PoE Currency Exchange Flip Finder

**Owner:** tapoox
**Last updated:** 2026-08-05

**Related docs:** [ARCHITECTURE.md](ARCHITECTURE.md) (resilience & system design) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external API contracts) · [TECH_STACK.md](TECH_STACK.md) (technology decisions) · [SCHEMA.md](SCHEMA.md) (database schema) · [CODE_STYLE.md](CODE_STYLE.md) (Java code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

## 1. Overview

Path of Exile 1 introduced the in-game **Currency Exchange**, an order-book-style market for trading currency directly (no player trading required). Prices on it are inefficient in predictable ways: spreads between instant and competitive rates, and gaps between what the Exchange charges and what NPC vendors or divination card turn-ins pay out.

This product is a website that scans those inefficiencies and surfaces profitable currency flips a player can execute manually in-game. It is a **read-only analysis tool** — it does not trade on the player's behalf.

## 2. Problem Statement

Finding a profitable flip today means manually comparing Currency Exchange rates against vendor recipe math or divination card economics — tedious enough that most players don't bother, even though real margin exists. There's no single place that ranks these opportunities by profitability, liquidity, and cost to execute.

## 3. Goals

- Surface currently profitable currency flips, ranked and sortable.
- Cover three distinct flip mechanics (below), each as its own view.
- Keep the user in the loop: show the trade steps and let them execute manually in-game.

## 4. Non-Goals

- No automated trading / bot execution — this is analysis only, and automating trades likely violates GGG's ToS.
- No alerting/notifications (watchlists, thresholds).
- No Path of Exile 2 support.
- No general item flipping (uniques, gear, etc.) — currency, vendor recipes, and divination cards only.
- No historical trend charts.

## 5. Target User

PoE players who enjoy the trading/economy side of the game and want a fast way to check "is there free money on the table right now" before or during a play session. Primary user is the builder (tapoox); designed for manual browsing, not automation.

## 6. Terminology

| Term | Meaning |
|---|---|
| **Currency Exchange** | In-game order-book market for trading currency directly. |
| **Instant rate** | The rate you get filling into existing orders immediately (like pressing Alt in-game to see the top-of-book vs the quoted default). |
| **Competitive rate** | A better rate available by placing your own limit order and waiting for it to fill — slower, but higher yield. |
| **Gold** | Resource consumed to place/fill orders on the Currency Exchange; earned by selling items to vendors. Not modeled in v1 — see [DATA_SOURCES.md § Gold Cost](DATA_SOURCES.md#gold-cost-not-available). |
| **Vendor recipe** | Fixed-ratio conversion available by selling specific items to an NPC vendor (e.g., Scrolls of Wisdom → Portal Scrolls). |
| **Divination card** | Collectible card; turning in a full stack (set) yields a fixed reward. Only cards with a **fixed, non-random currency reward** are in scope — no gamble cards (e.g., cards that reward random uniques, or chance-based outcomes). |
| **Margin** | Profit % or absolute profit for a given flip after accounting for all conversion steps. |

## 7. Core Features

### 7.1 Feature A — Vendor Recipe Arbitrage

Chains a Currency Exchange purchase with one or more vendor recipe conversions, then resells the result on the Exchange.

**Example (validates the concept):**
Buy 86 Orbs of Transmutation for 1 Chaos Orb on the Exchange → sell to vendor for 344 Scrolls of Wisdom → apply vendor recipe → 114 Portal Scrolls → sell Portal Scrolls on the Exchange for ~2 Chaos Orbs. Net: ~2x on the original Chaos Orb.

**Requirements:**
- List all currency → vendor-item conversion paths using vendor sell rates and known vendor recipes (sourced from the [PoE Wiki Currency page](https://www.poewiki.net/wiki/Currency) and item-specific pages, e.g. [Scroll of Wisdom](https://www.poewiki.net/wiki/Scroll_of_Wisdom)).
- For each path, compute: buy cost (Exchange), intermediate vendor output, final recipe output, resale value (Exchange), and net margin.
- Rank/sort by margin %, absolute profit, and volume available at the buy rate.
- Show the full step-by-step recipe (what to buy, what to vendor, what recipe to apply, what to sell) so the user can execute it manually.

### 7.2 Feature B — Exchange Spread/Margin Finder

For each currency pair on the Exchange, compare the instant-fill rate against the competitive (limit-order) rate and surface the spread as a flip opportunity.

**Example:** Scroll of Wisdom instant sell is 185:1 Chaos; competitive rate is 366:1 Chaos. Buying in at the competitive rate (accepting slower fill) nearly doubles the yield vs. instant.

**Requirements:**
- Pull both instant and competitive/order-book rates per currency pair.
- Compute margin between the two.
- **Every opportunity must start and sell in Chaos Orb or Divine Orb** — the two currencies a player actually accumulates and already holds. A pair between two other currencies (e.g. Scroll of Wisdom vs. Portal Scroll) isn't something a player can act on without already holding that specific altcoin, so it's excluded entirely rather than shown. When a pair has Chaos on one side and Divine on the other, Chaos is the anchor (since profit, below, is always Chaos-denominated and that pair needs no rate conversion).
- **Profit is always expressed in Chaos Orb**, regardless of which base currency (Chaos or Divine) the opportunity starts/sells in — a "+1" profit always means at least 1 real Chaos Orb, per [TECH_STACK.md](TECH_STACK.md)'s row design (profit shown next to a Chaos icon, not the start currency's icon). A Divine-anchored opportunity's profit is converted to Chaos using the current Chaos/Divine exchange rate; if that rate isn't available for some reason, the opportunity is dropped rather than shown with a misleading unit.
- **Buy/sell prices are undercut suggestions, not the raw historical extremes.** Currency can't be traded in fractions, and posting a limit order at the literal best-ever observed rate rarely gets filled. Both reference rates (the more/less favorable of the hour's two observed extremes) are floored to whole numbers, then undercut by 1 unit in whichever direction makes the posted order more attractive than the going rate to a counterparty — the buy price steps down, the sell price steps up. Margin, profit, and the "Via" quantity are all computed from these suggested prices, not the raw extremes, and the suggested buy/sell prices are shown in the Via column's detail line (e.g. "buy 365:1 · sell 186:1"). If the buy side can't sustain a -1 undercut (the reference rate doesn't clear 1 whole unit — e.g. buying Divine Orb with a single Chaos Orb), the opportunity is dropped rather than shown with a meaningless price.
- **Any opportunity with zero volume is dropped entirely, across every technique (this applies to Feature E's Bulk Buy too, not just Exchange Spread).** A leg with no real stock behind it produced its rate from stale/outlier data rather than an actual tradeable market — the ratio math can still look internally consistent (e.g. "≈10 Chaos → 1 Divine" via a nearly-untraded intermediary), but there's no counterparty to actually fill it. This is a floor applied once at the point where all techniques' results are merged, not a per-technique rule.
- Sortable by margin and volume (depth available at the competitive rate).
- Since competitive-rate fills are slower and not guaranteed, flag this tradeoff clearly in the UI (e.g., a "fill speed" caveat or badge) rather than presenting it as equivalent to an instant flip.

> **Data availability note:** the public Currency Exchange API does not expose a live order book (see [DATA_SOURCES.md](DATA_SOURCES.md)) — only an hourly range of rates that actually filled (`lowest_ratio`/`highest_ratio`). This feature will be built against that hourly range as a proxy for the instant-vs-competitive spread, refreshed on demand rather than live.

### 7.3 Feature C — Divination Card Flip Finder

Finds divination cards that can be bought (as a full stack) via the Currency Exchange, turned in, and sold back for a **predictable** profit.

**Requirements:**
- Only include cards whose turn-in reward is a **fixed currency amount** — explicitly exclude gamble-style cards (random unique/item rewards, chance-outcome cards like The Void, item-conversion cards, etc.).
- Compute: cost to buy a full stack via the Exchange, reward received, resale value of that reward via the Exchange, and net margin.
- Sortable by margin, absolute profit, and volume/availability of the card stack on the Exchange.

### 7.4 Feature D — League Selector

A dropdown in the site settings (top right of the page) that scopes all three views (Features A–C) to a single league. Selecting a league is global to the session, not per-view.

**Requirements:**
- The league list must be fully dynamic — no hardcoded league names or IDs anywhere in the code. When GGG launches a new challenge league, it must appear in the dropdown automatically, without a code change or deploy.
- The list must only include leagues that actually have Currency Exchange activity. Leagues that don't support trading (Solo Self-Found variants) must never appear, since flip-finding is meaningless there.
- Default selection is the current mainline challenge league (not Standard).
- A manual refresh control (icon button next to the dropdown) re-fetches the league list on demand, without a full page reload. There is no caching layer for this list — a full page reload already re-fetches it live from GGG on every load, so the button exists purely for convenience within an already-open tab (e.g. a new challenge league just launched). If the currently selected league still exists in the refreshed list, the selection is preserved; only a selection that disappeared falls back to the default. This is distinct from Feature G's manual refresh, which re-runs Currency Exchange ingestion, not the league list.

**How this is derived:** see [ARCHITECTURE.md § League Resolution](ARCHITECTURE.md#league-resolution) for the exact algorithm, and [DATA_SOURCES.md § League List](DATA_SOURCES.md#league-list) for the verified API facts backing it.

### 7.5 Feature E — Bulk Buy

Finds a third item that has active Currency Exchange markets against two different currencies, where buying that item with currency A and immediately reselling it for currency B yields more of B than trading A directly for B on the Exchange. (This is a triangular arbitrage in trading terms — see [TECH_STACK.md](TECH_STACK.md) — but "Bulk Buy" is the name used in the UI and throughout this doc set, since that's the more intuitive framing for a PoE player.)

**Example:** Buy a Stacked Deck using Divine Orbs, then sell that same Stacked Deck for Chaos Orbs — if the implied Divine→Chaos rate through the Stacked Deck beats the direct Divine→Chaos Exchange rate, the difference is pure profit, entirely within the Exchange (no vendor, no card turn-in required).

**Requirements:**
- Uses only Currency Exchange data already covered in [DATA_SOURCES.md](DATA_SOURCES.md) — no new external data source is needed. This is a graph-traversal analysis over the same market pairs used elsewhere: for any item tradeable against multiple currencies, compute the implied cross-rate and compare it to the direct rate for that currency pair (if one exists).
- **Currency A and currency B are restricted to Chaos Orb and Divine Orb** — the same two currencies Feature B is anchored on, since those are the only ones a player is assumed to already hold (see § 7.2). The search is therefore: for every item that trades against both Chaos and Divine, does routing through it beat the direct Chaos↔Divine rate? Both directions (Chaos→item→Divine and Divine→item→Chaos) are computed independently, since the realistic buy/sell pricing below isn't symmetric — one direction can be profitable while the reverse isn't.
- **The buy leg uses Feature B's competitive undercut price; the sell (resell) leg uses the plain market rate instead.** Posting two unfilled limit orders back to back is riskier than posting one — especially on a large, often-illiquid intermediary stack — so only entering the position is priced competitively (round down, then undercut by 1, same as § 7.2). Exiting it assumes dumping into demand that's already been shown to exist this hour: the hour's worse-but-real observed rate, floored, with **no** further undercut push. (Feature B's own round-trip flips are unaffected by this — they still undercut both legs.) The "direct A→B rate" used as the comparison baseline is, separately, the raw, non-undercut, averaged Chaos/Divine rate, not a real order suggestion — it's a reference to beat, not a trade being proposed.
- Compute: cost to acquire the intermediary item in currency A, proceeds from reselling it in currency B, **net margin versus the direct A→B rate** (not versus the starting amount — start and sell are different currencies here, so "gain over what you put in" isn't a meaningful ratio the way it is for Feature B's same-currency round trip). Profit is always converted to Chaos, per § 7.2's rule.
- If the Chaos↔Divine reference rate isn't available at all, no Bulk Buy opportunities are produced (nothing to compare against).
- **The reference trade size is scaled per direction to avoid showing a meaningless fraction.** "Bulk Buy" refers to buying the intermediary item in bulk quantity in one Exchange trade (the Via amount, e.g. "9000 Orb of Alteration"), not to starting from a large pile of currency — but always starting from exactly 1 unit of currency A (Feature B's convention) produces an unreadable result when A is Chaos and B is Divine, since 1 Chaos converts to a tiny fraction of a Divine (e.g. "1 Chaos → 0.005 Divine"). The Chaos→item→Divine direction is instead scaled so it always ends at **exactly 1 Divine sold**, showing however much Chaos and how much of the item that actually takes (e.g. "≈230 Chaos → 9000 Orb of Alteration → 1 Divine") — this reads the way a player actually thinks about the trade ("how much Chaos does it cost me to get a Divine this way?") and lines up directly with the displayed direct-rate comparison. The Divine→item→Chaos direction keeps Feature B's "start from 1" convention unchanged, since starting from 1 Divine already produces a legible Chaos amount. Margin is unaffected by this scaling (it's a ratio); profit scales proportionally with the reference trade size, same as it would if a player actually multiplied the trade up.
- Sortable by margin, absolute profit, and volume (bounded by whichever leg of the trade — the buy or the resell — has less depth).
- Show both legs explicitly (buy item X with A, sell item X for B) so the user can execute it manually, consistent with Features A–C.

### 7.6 Feature F — Data Freshness Banner

A persistent banner at the top of the page showing the exact moment the currently-displayed data was last refreshed, alongside the main Currency Exchange refresh control itself (the trigger for the ingestion described in [ARCHITECTURE.md § Currency Exchange Ingestion](ARCHITECTURE.md#currency-exchange-ingestion-change-stream--checkpoint-model) — distinct from Feature G's league-list/item-icon reloads).

**Requirements:**
- Always visible, not something the user has to look for — this is what makes the "manual refresh" model ([ARCHITECTURE.md](ARCHITECTURE.md)) trustworthy: staleness is never silently hidden.
- Shows an absolute timestamp, not a vague relative time like "a few minutes ago" — full date, hour, minute, and millisecond.
- Sourced from `active_generation_refreshed_at` in [SCHEMA.md § Ingestion state and market data](SCHEMA.md#ingestion-state-and-market-data) — the moment the currently-active generation was made live, not the underlying data's own hourly granularity. Those are two different things: the banner tells the user exactly when the app last successfully pulled data, not how fresh the Currency Exchange's own hourly aggregates are.
- **The refresh action is capped per click, not guaranteed to fully catch up in one press.** If the app has been idle a long time (or this is the very first refresh ever), one click may only make partial progress — the banner's timestamp still advances to reflect whatever was successfully committed, and the user just clicks refresh again to continue catching up. This must be visible, not silent: the UI should indicate when a refresh completed only partially (e.g. "click refresh again to finish catching up") rather than implying the single click fully updated everything.

### 7.7 Feature G — Manual Data Source Refresh

Settings-area controls to force a re-fetch of individual data sources, independent of the main Currency Exchange refresh.

**Requirements:**
- **One real, independent reload action: league list.** Sourced from a live, no-auth GGG API ([DATA_SOURCES.md](DATA_SOURCES.md)), so reloading it is just re-running that adapter — this is the existing league-list refresh button next to the League Selector ([§ 7.4](#74-feature-d--league-selector)).
- **No reload action for item icons, vendor recipes, or divination card data — same category, different reasons.** Item icons are vendored into a bundled resource, not fetched live in production at all: GGG blocks the `/api/trade/*` path outright from datacenter IPs (confirmed against Render across multiple hostnames and headers — see [DATA_SOURCES.md § Item Icons](DATA_SOURCES.md#item-icons)), so there is no live server the app itself can hit. Vendor recipes and divination card data are manually captured from the PoE Wiki, not scraped live — the wiki's anti-bot protection blocks automated fetches (see [DATA_SOURCES.md](DATA_SOURCES.md)). In both cases there is no live source this app can re-fetch from at request time; a reload button in the UI would call nothing real — don't build one. Item icons are refreshed by a developer running `backend/scripts/refresh-item-icons-catalog.sh` (or the `/refresh-item-icons-catalog` Claude Code skill) from a residential network, committing the result, and redeploying — the same "new migration or manual re-entry" update model as vendor recipes/divination cards ([TECH_STACK.md](TECH_STACK.md), [SCHEMA.md](SCHEMA.md)), not a runtime action a user ever triggers.

### 7.8 Feature H — Technique Filters

Checkboxes above the results table, one per flip-finding mechanism, letting the user show or hide each independently.

**Requirements:**
- One checkbox per technique: Vendor Recipe (7.1), Exchange Spread (7.2), Divination Card (7.3), Triangular Arbitrage (7.5).
- All checked by default — the default view shows everything; filtering is opt-out, not opt-in.
- A purely client-side display filter over the already-fetched result set. It does not change what the backend computes — data volumes here are small enough (per [DATA_SOURCES.md](DATA_SOURCES.md)) that computing all four techniques on every refresh and filtering the display is simpler than a backend filter parameter, and keeps this feature entirely in the frontend layer.

### 7.9 Feature I — Column Sorting & Threshold Filters

Sortable Margin, Profit, and Volume columns, plus a minimum-threshold filter per column.

**Requirements:**
- Clicking the Margin, Profit, or Volume column header sorts the table by that column, toggling ascending/descending on repeated clicks, with a visible indicator of the current sort column and direction.
- Each of those three columns also gets a minimum-threshold numeric filter (e.g. "volume ≥ 50") so the user can narrow out low-value or illiquid opportunities.
- Combines with Feature H — sorting, filtering, and technique checkboxes all apply to the same client-side result set together.

### 7.10 Feature J — Favorites

Right-click a row to pin it as a favorite. Favorited flips always render above the rest of the table, visually distinct.

**Requirements:**
- Right-click a row → mark/unmark as favorite (no separate "manage favorites" screen needed for v1).
- **Favoriting identifies the trade route, not the computed instance.** Since flip opportunities are recomputed fresh on every refresh and never persisted ([SCHEMA.md § Deliberately not a table](SCHEMA.md#deliberately-not-a-table-flip-opportunities)), a favorite is keyed by which currencies/items are involved and via which mechanism (e.g. "Transmutation → Chaos via vendor recipe", "Divine → Stacked Deck → Chaos") — never by the margin/profit/volume values shown at the moment it was favorited, since those change every refresh.
- **Stored client-side (browser storage), not server-side.** This app has no user-account system ([TECH_STACK.md](TECH_STACK.md) Credential Policy) — favorites are a personal, per-browser preference, not synced across devices or sessions elsewhere.
- Favorited rows render as their own group above the regular table, sorted/filtered by the same Feature I rules as the main table.
- If a favorited route doesn't appear in the current computed results (e.g. no longer profitable, or filtered out by Feature H/I), it simply doesn't show — no placeholder or stale-favorite indicator needed for v1.
- Visual treatment: distinct row background plus a star icon, per [TECH_STACK.md](TECH_STACK.md).

### 7.11 Feature K — Build Info Footer

A small full-width bar at the bottom of the page, mirroring the header bar's style, showing exactly which frontend build is currently loaded: the short git commit hash and the build's timestamp.

**Requirements:**
- Shows the short (7-character) git commit hash and the build date/time, both sourced at frontend build time — Vite injects them as compile-time constants when `npm run build` runs. No runtime API call, no backend involvement.
- Exists to answer "is this actually the new code?" directly from the page itself, rather than guessing from Render/Vercel's deploy-hook timing — this project's deploys are asynchronous (a deploy hook firing doesn't mean the rebuild has finished), which has caused real confusion earlier in development (a screenshot taken moments after triggering a deploy showed stale output purely because Render/Vercel hadn't finished rebuilding yet).
- If git metadata isn't available in the build environment (e.g. no `.git` directory present), the bar shows "unknown" for the hash rather than failing the build.
- Timestamp format matches Feature F's freshness stamp (§ 7.6): absolute local time, `YYYY-MM-DD HH:MM:SS.mmm` — not a vague relative time.

## 8. Success Criteria

- The three views each return correct, sortable results that match manual in-game verification for a sample of flips.
- Data staleness is always visible via the Feature F banner — an exact timestamp, not a vague relative time.
- The tool gets used before/during play sessions to find real flips.

## 9. Future Considerations

- Gold cost: no reliable data source exists today (no API field, no official formula — see [DATA_SOURCES.md](DATA_SOURCES.md)). Revisit if GGG ever exposes this, or if a trustworthy formula/source emerges.
- Alerts/watchlists: notify when a specific flip crosses a profitability threshold.
- Historical margin tracking / trend charts.
- League-start-specific views (early-league inefficiencies tend to be larger).
- PoE2 support, if/when its economy stabilizes and exposes similar mechanics.
