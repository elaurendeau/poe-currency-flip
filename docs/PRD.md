# PRD: PoE Currency Exchange Flip Finder

**Owner:** tapoox
**Last updated:** 2026-08-07

**Related docs:** [ARCHITECTURE.md](ARCHITECTURE.md) (resilience & system design) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external API contracts) · [TECH_STACK.md](TECH_STACK.md) (technology decisions) · [SCHEMA.md](SCHEMA.md) (database schema) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

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
- **Buy/sell prices are undercut suggestions, not the raw historical extremes.** Currency can't be traded in fractions, and posting a limit order at the literal best-ever observed rate rarely gets filled. The buy reference rate (the more favorable of the hour's two observed extremes) is floored to a whole number, then undercut by 1 unit to make the posted order more attractive than the going rate to a counterparty. Margin, profit, and the "Via" quantity are all computed from these suggested prices, not the raw extremes, and the suggested buy/sell prices are shown in the Via column's detail line (e.g. "buy 365:1 · sell 251:1"). **If the buy side can't sustain a -1 undercut anchored on the base currency (the reference rate doesn't clear 1 whole unit — e.g. buying Divine Orb with a single Chaos Orb), the pair retries quoting the other way round instead** ("Chaos per 1 Divine" rather than "Divine per 1 Chaos") — the same auto-detected per-leg fallback § 7.3's Divination Card already applies to its own legs. Start/Sell stay anchored on Chaos or Divine either way; only which side the rate is quoted "per 1 unit of" changes, scaling the Start/Via/Sell quantities by multiplication instead of division for the retried orientation. The opportunity is only dropped if *neither* orientation clears a whole unit.
- **The sell reference rate is the hour's volume-weighted average rate (total traded volume of one side ÷ the other), not the raw "other" extreme.** A real production bug (verified against live GGG data 2026-08-08): the hourly `lowest_ratio`/`highest_ratio` extremes can include a single thin outlier fill far from the real market — e.g. Jeweller's Orb showed a raw extreme pair of 1:75 and 1:1 against Chaos in one hour, where the 1:1 side was a lone fluke trade while the real in-game competitive rate that hour was ~53–66:1. Using that raw extreme directly floored the suggested sell price to 2, manufacturing a ~3600% fake margin that dominated any margin-sorted view of the opportunities list. The volume-weighted average is immune to this: a 1-unit outlier fill barely moves a total-volume ratio, while it can single-handedly become one of only two raw extremes. This average is mathematically guaranteed to fall between the hour's two raw extremes, so it can never invert the buy/sell direction. It's floored, then undercut by +1 the same way as before. This applies only to the round-trip sell reference (`suggested_sell_price`); the one-directional dump reference used by Bulk Buy (§ 7.5) and Divination Card's resale leg (§ 7.3) intentionally keeps using the raw buy-side extreme, since that's modeling an instant, no-waiting sale rather than a patient competitive one.
- **Any opportunity with zero volume is dropped entirely, across every technique (this applies to Feature E's Bulk Buy too, not just Exchange Spread).** A leg with no real stock behind it produced its rate from stale/outlier data rather than an actual tradeable market — the ratio math can still look internally consistent (e.g. "≈10 Chaos → 1 Divine" via a nearly-untraded intermediary), but there's no counterparty to actually fill it. This is a floor applied once at the point where all techniques' results are merged, not a per-technique rule.
- **A Divine-anchored opportunity is dropped if it would buy more than 1 whole unit of the other currency** (e.g. "1 Divine Orb → 3199 Orb of Fusing"), even when the underlying rate and liquidity are perfectly real. This reads as a bulk-scale trade rather than the single competitive-order spread this feature is about, per direct user feedback. The pair still retries the inverted orientation first (per the undercut-viability rule above) — if that inverted quote is itself viable (the item is worth roughly 1 Divine or more), the opportunity is kept, quoted "Divine per 1 [item]" instead. It's only dropped outright when neither orientation avoids a bulk-sized quantity. **Chaos-anchored opportunities are exempt from this rule** — Chaos is already the smallest-value base currency, so "1 Chaos buys many cheap items" (e.g. "1 Chaos → 74 Jeweller's Orb") is this feature's normal, expected shape, not a bulk trade.
- Sortable by margin and volume (depth available at the competitive rate).
- Since competitive-rate fills are slower and not guaranteed, flag this tradeoff clearly in the UI (e.g., a "fill speed" caveat or badge) rather than presenting it as equivalent to an instant flip.

> **Data availability note:** the public Currency Exchange API does not expose a live order book (see [DATA_SOURCES.md](DATA_SOURCES.md)) — only an hourly range of rates that actually filled (`lowest_ratio`/`highest_ratio`). This feature will be built against that hourly range as a proxy for the instant-vs-competitive spread, refreshed on demand rather than live.

### 7.3 Feature C — Divination Card Flip Finder

Finds divination cards that can be bought (as a full stack) via the Currency Exchange, turned in, and sold back for a **predictable** profit.

**Requirements:**
- Only include cards whose turn-in reward is a **fixed currency amount** — explicitly exclude gamble-style cards (random unique/item rewards, chance-outcome cards like The Void, item-conversion cards, etc.). A card excluded this way is kept in the reference data with its exclusion flagged, not omitted, so the decision stays visible ([DATA_SOURCES.md](DATA_SOURCES.md)).
- Compute: cost to buy a full stack via the Exchange, reward received, resale value of that reward via the Exchange, and net margin.
- Sortable by margin, absolute profit, and volume/availability of the card stack on the Exchange.
- **The buy leg (acquiring the card stack) and the resale leg (selling the reward) each independently prefer a Chaos-side market for that leg's currency, falling back to a Divine-side market if no Chaos market exists.** The two legs are unrelated trades — the buy leg's currency choice doesn't constrain the resale leg's.
- **The buy leg is priced competitively (the same undercut convention as § 7.2); the resale leg is priced at the plain market rate, never the round-trip-favorable rate.** Same reasoning as § 7.5's Bulk Buy sell leg: this is a one-directional sell into existing demand, not a round-trip order.
- **Both legs re-orient if the "other" side turns out to be worth more than 1 base unit.** Quoting "card/reward units per 1 Chaos" floors to 0 for something worth e.g. 200 Chaos, silently discarding an opportunity with real volume and stock (a real production incident: a ~200c card discarded despite live tradeable markets). When that happens, the leg retries quoting "Chaos per 1 card/reward unit" instead — an auto-detected fallback per leg, not a hardcoded direction, since a card's value relative to Chaos/Divine isn't known ahead of time.
- If no Chaos↔Divine reference rate is available at all, Divination Card produces no opportunities (same rule as § 7.5's Bulk Buy — nothing to convert profit into).
- If either leg (buy or resale) can't be priced against Chaos or Divine at all, that card silently contributes no opportunity — not an error, not a zero-value row.

### 7.4 Feature D — League Selector

A dropdown in the site settings (top right of the page) that scopes all three views (Features A–C) to a single league. Selecting a league is global to the session, not per-view.

**Requirements:**
- The league list must be fully dynamic — no hardcoded league names or IDs anywhere in the code. When GGG launches a new challenge league, it must appear in the dropdown automatically, without a code change or deploy.
- The list must only include leagues that actually have Currency Exchange activity. Leagues that don't support trading (Solo Self-Found variants) must never appear, since flip-finding is meaningless there.
- Default selection is the current mainline challenge league (not Standard).
- A manual refresh control (icon button next to the dropdown) re-fetches the league list on demand, without a full page reload. There is no caching layer for this list — a full page reload already re-fetches it live from GGG on every load, so the button exists purely for convenience within an already-open tab (e.g. a new challenge league just launched). If the currently selected league still exists in the refreshed list, the selection is preserved; only a selection that disappeared falls back to the default. This is distinct from Feature G's manual refresh, which re-runs Currency Exchange ingestion, not the league list.

**How this is derived:** see [ARCHITECTURE.md § League Resolution](ARCHITECTURE.md#league-resolution) for the exact algorithm, and [DATA_SOURCES.md § League List](DATA_SOURCES.md#league-list) for the verified API facts backing it.

### 7.5 Feature E — Bulk Buy

Finds a third item that has active Currency Exchange markets against both Chaos and Divine, where buying that item with a Divine Orb and immediately reselling it for Chaos Orbs yields more Chaos than trading the Divine directly for Chaos on the Exchange. (This is a triangular arbitrage in trading terms — see [TECH_STACK.md](TECH_STACK.md) — but "Bulk Buy" is the name used in the UI and throughout this doc set, since that's the more intuitive framing for a PoE player.)

**Example:** Buy a Stacked Deck using a Divine Orb, then sell that same Stacked Deck for Chaos Orbs — if the implied Divine→Chaos rate through the Stacked Deck beats the direct Divine→Chaos Exchange rate, the difference is pure profit, entirely within the Exchange (no vendor, no card turn-in required).

**Requirements:**
- Uses only Currency Exchange data already covered in [DATA_SOURCES.md](DATA_SOURCES.md) — no new external data source is needed. This is a graph-traversal analysis over the same market pairs used elsewhere: for any item tradeable against multiple currencies, compute the implied cross-rate and compare it to the direct rate for that currency pair (if one exists).
- **Only the Divine→item→Chaos direction is computed** — the reverse (buy with Chaos, resell for Divine) is a real, computable arbitrage too, but per direct user feedback it's not the trade this feature is for: Bulk Buy is specifically "convert Divine you're already holding into more Chaos than a direct sale would get," not a general two-way triangular scan. Chaos and Divine remain the only two currencies either leg trades in, per § 7.2.
- **The buy leg uses Feature B's competitive undercut price; the sell (resell) leg uses the plain market rate instead.** Posting two unfilled limit orders back to back is riskier than posting one — especially on a large, often-illiquid intermediary stack — so only entering the position is priced competitively (round down, then undercut by 1, same as § 7.2). Exiting it assumes dumping into demand that's already been shown to exist this hour: the hour's worse-but-real observed rate, floored, with **no** further undercut push. (Feature B's own round-trip flips are unaffected by this — they still undercut both legs.) The "direct Divine→Chaos rate" used as the comparison baseline is, separately, the raw, non-undercut, averaged Chaos/Divine rate, not a real order suggestion — it's a reference to beat, not a trade being proposed.
- Compute: cost to acquire the intermediary item (1 Divine, competitively), proceeds from reselling it for Chaos, **net margin versus the direct Divine→Chaos rate** (not versus the starting amount — start and sell are different currencies here, so "gain over what you put in" isn't a meaningful ratio the way it is for Feature B's same-currency round trip). Profit is already Chaos-denominated, needing no conversion.
- If the Chaos↔Divine reference rate isn't available at all, no Bulk Buy opportunities are produced (nothing to compare against).
- Start is always exactly 1 Divine Orb (Feature B's convention), which already produces a legible Chaos amount on the Sell side — no special trade-size scaling is needed, unlike a hypothetical Chaos-start direction where 1 Chaos would convert to an unreadable fraction of a Divine.
- Sortable by margin, absolute profit, and volume (bounded by whichever leg of the trade — the buy or the resell — has less depth).
- Show both legs explicitly (buy item X with A, sell item X for B) so the user can execute it manually, consistent with Features A–C.

### 7.6 Feature F — Data Freshness Banner

A persistent banner at the top of the page showing the exact moment the currently-displayed data was last refreshed, alongside the main Currency Exchange refresh control itself (the trigger for the ingestion described in [ARCHITECTURE.md § Currency Exchange Ingestion](ARCHITECTURE.md#currency-exchange-ingestion-change-stream--checkpoint-model) — distinct from Feature G's league-list/item-icon reloads).

**Requirements:**
- Always visible, not something the user has to look for — this is what makes the "manual refresh" model ([ARCHITECTURE.md](ARCHITECTURE.md)) trustworthy: staleness is never silently hidden.
- Shows an absolute timestamp, not a vague relative time like "a few minutes ago" — full date, hour, minute, and millisecond.
- Sourced from `active_generation_refreshed_at` in [SCHEMA.md § Ingestion state and market data](SCHEMA.md#ingestion-state-and-market-data) — the moment the currently-active generation was made live, not the underlying data's own hourly granularity. Those are two different things: the banner tells the user exactly when the app last successfully pulled data, not how fresh the Currency Exchange's own hourly aggregates are.
- **The refresh action is capped per click, not guaranteed to fully catch up in one press.** If the app has been idle a long time (or this is the very first refresh ever), one click may only make partial progress — the banner's timestamp still advances to reflect whatever was successfully committed, and the user just clicks refresh again to continue catching up. This must be visible, not silent: the UI should indicate when a refresh completed only partially (e.g. "click refresh again to finish catching up") rather than implying the single click fully updated everything.
- **Clicking refresh must also refresh the displayed flip opportunities, not just this banner's timestamp.** These are driven by two independent data fetches; without an explicit link between them, the banner can advance to a new ingestion generation while the opportunities table keeps showing rows computed from the previous one -- a real bug found in production, where a Bulk Buy row kept showing a stale rate from an older ingested hour after the timestamp had already moved forward. The opportunities fetch must be retriggered whenever the active generation's timestamp changes, not only when the selected league changes.
- **A temporary status banner, separate from the always-visible timestamp above, gives explicit feedback for a refresh action in progress and its outcome.** Found necessary after real usage: GGG's Currency Exchange data only changes once per hour (see [DATA_SOURCES.md](DATA_SOURCES.md)), so a refresh clicked within the same hour as the last one correctly finds nothing new and completes in well under a second -- with only the small refresh-icon spin as feedback, this reads as "the button did nothing," not as "correctly confirmed you're already up to date." Requirements:
  - Shown at the top of the page while a refresh (this one or Feature G's league refresh) is in progress, and briefly after it completes, then auto-dismisses -- it is not a second persistent status indicator competing with the timestamp above.
  - **While in progress:** a neutral "refreshing" message, shown for the actual duration of the request. No fixed minimum duration is imposed -- an already-caught-up refresh legitimately completing in under a second is correct behavior, not a bug to mask with an artificial delay.
  - **On completion, the message is one of three distinct outcomes, not a single generic "done":**
    1. New data was found and ingested: states that a refresh happened (plain confirmation).
    2. Already caught up, nothing new found: states this explicitly, **plus an estimate of when new data will actually become available** -- computed from the real checkpoint (the next hour boundary after the last successfully processed hour), not a guess or a fixed countdown, since GGG's hourly bucket boundary is a known, exact value once a checkpoint exists.
    3. Partial progress (the per-click cap was hit before reaching the current hour): states that more remains and another click is needed -- this is the existing condition already described above (the "click refresh again" case); the temporary banner surfaces it too, in addition to the persistent partial-progress text already required above.
  - **A failed refresh does not use this banner.** Failure already has its own persistent, explicit indicator (the existing error state) -- this banner is additive positive/neutral feedback for the success path, not a second, competing place to look for errors.

### 7.7 Feature G — Manual Data Source Refresh

Settings-area controls to force a re-fetch of individual data sources, independent of the main Currency Exchange refresh.

**Requirements:**
- **One real, independent reload action: league list.** Sourced from a live, no-auth GGG API ([DATA_SOURCES.md](DATA_SOURCES.md)), so reloading it is just re-running that adapter — this is the existing league-list refresh button next to the League Selector ([§ 7.4](#74-feature-d--league-selector)).
- **Uses the same temporary status banner described in [§ 7.6](#76-feature-f--data-freshness-banner)** for in-progress/completion feedback -- a neutral "refreshing leagues" message while in flight, a brief confirmation on success, auto-dismissing after. A league list has no "next available" concept the way ingestion's hourly bucket does (GGG's Leagues API can genuinely return something different on every call, e.g. a new challenge league launching), so there is no ETA-until-next-refresh message for this action -- only ingestion's completion message includes one. A failed refresh uses the existing persistent error state, not this banner, same rule as § 7.6.
- **No reload action for item icons, vendor recipes, or divination card data — same category, different reasons.** Item icons are vendored into a bundled resource, not fetched live in production at all: GGG blocks the `/api/trade/*` path outright from datacenter IPs (confirmed against Render across multiple hostnames and headers — see [DATA_SOURCES.md § Item Icons](DATA_SOURCES.md#item-icons)), so there is no live server the app itself can hit. Vendor recipes and divination card data are manually captured from the PoE Wiki, not scraped live — the wiki's anti-bot protection blocks automated fetches (see [DATA_SOURCES.md](DATA_SOURCES.md)). In both cases there is no live source this app can re-fetch from at request time; a reload button in the UI would call nothing real — don't build one. Item icons are refreshed by a developer running `app/scripts/refresh-item-icons-catalog.sh` (or the `/refresh-item-icons-catalog` Claude Code skill) from a residential network, committing the result, and redeploying — the same "new migration or manual re-entry" update model as vendor recipes/divination cards ([TECH_STACK.md](TECH_STACK.md), [SCHEMA.md](SCHEMA.md)), not a runtime action a user ever triggers.

### 7.8 Feature H — Technique Filters

Checkboxes above the results table, one per flip-finding mechanism, letting the user show or hide each independently.

**Requirements:**
- One checkbox per technique: Vendor Recipe (7.1), Exchange Spread (7.2), Divination Card (7.3), Triangular Arbitrage (7.5).
- All checked by default — the default view shows everything; filtering is opt-out, not opt-in.
- A purely client-side display filter over the already-fetched result set. It does not change what the backend computes — data volumes here are small enough (per [DATA_SOURCES.md](DATA_SOURCES.md)) that computing all four techniques on every refresh and filtering the display is simpler than a backend filter parameter, and keeps this feature entirely in the frontend layer.
- **Persisted client-side (browser storage), surviving a full page reload** — same mechanism and per-browser scope as Favorites (§7.10): a personal preference, not synced across devices or sessions elsewhere. A first-ever visit (nothing saved yet) falls back to the all-checked default above.

### 7.9 Feature I — Column Sorting & Threshold Filters

Sortable Margin, Profit, and Volume columns, plus a minimum-threshold filter per column.

**Requirements:**
- Clicking the Margin, Profit, or Volume column header sorts the table by that column, toggling ascending/descending on repeated clicks, with a visible indicator of the current sort column and direction.
- Each of those three columns also gets a minimum-threshold numeric filter (e.g. "volume ≥ 50") so the user can narrow out low-value or illiquid opportunities.
- Combines with Feature H — sorting, filtering, and technique checkboxes all apply to the same client-side result set together.
- **The Start column additionally gets a maximum-value numeric filter** (e.g. "show nothing needing more than 10 starting Chaos"), letting a player with limited capital hide opportunities they can't actually afford to enter — independent of the minimum-threshold filters above, and not sortable (Start isn't a sort column). Since a row's Start can be denominated in either Chaos Orb or Divine Orb (§7.2), this filter compares against the Chaos-normalized equivalent of the starting amount, not its raw displayed quantity, so the cap means the same thing regardless of which base currency a given row happens to anchor on.
- **Sort column/direction and threshold values (including the Start max) are persisted client-side (browser storage), surviving a full page reload** — same mechanism and per-browser scope as Favorites (§7.10). A first-ever visit falls back to the defaults above (Margin, descending, no thresholds set, no Start cap).

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

### 7.12 Feature L — Ratio Calculator

A small floating utility, independent of the flip-finding features above, for working out whole-number trade ratios. Not tied to live market data — a standalone helper for a common manual task: PoE bulk trade listings require whole-number price ratios (e.g. an Exchange listing must state something like "31:2", not "15.5:1"), so a player who knows the decimal rate they want needs the smallest — or a nearby — whole-number pair that matches it.

**Requirements:**
- Presented as a floating launcher button anchored to the bottom-left corner of the viewport; clicking it pops a small panel open above the button, and clicking again (or its own close control) pops it closed. Does not require navigating away from the main flip table.
- Three fields: **Ratio** (top, full width) accepting free-form input like `15.5:1`, `15.5/1`, `31:2`, or a bare number (implicitly `:1`); **Left** and **Right** (below, side by side, separated by a colon) holding a whole-number pair.
- Entering a valid ratio fills Left/Right with the smallest whole-number pair that matches it exactly (e.g. `15.5:1` → `31:2`), derived from the ratio's own decimal precision rather than a divided-out float, so it's exact rather than an approximation.
- Editing either Left or Right directly recalculates the other to the nearest whole number that keeps the entered ratio (e.g. changing Left to `145` sets Right to `9`, since 145/15.5 ≈ 9.35).
- Whichever field the user just edited is treated as the fixed anchor for that recalculation and for both suggestion lists below it.
- **When the resulting pair doesn't hit the ratio exactly, two sections appear below the fields instead of a single approximate value:**
  - **"Closest matches"** — normally exactly two rows: the anchor paired with the counterpart rounded down and with it rounded up (e.g. for target 15.5 and anchor Left=145: `≈16.11:1 → 145:9` and `≈14.5:1 → 145:10`). Never just whichever direction happens to round nearest — both directions are shown, since either can be the one the player actually wants to list at. **Exception:** when the anchor value is small enough that rounding the counterpart *down* would hit zero (e.g. anchor Left=1 against a target ratio of 15.5, where the down-rounded counterpart is 0), that row is dropped rather than shown with a meaningless non-positive side — leaving just the one usable row.
  - **"Other whole-ratio options"** — up to two further suggestions for the pair at the nearest whole-number *ratios* above and below the target itself (e.g. `16:1 → 145:9` and `15:1 → 145:10`), letting the user pick a rounder target ratio instead of the exact one. Omitted when the target ratio is itself already a whole number.
  - Both sections are omitted entirely whenever the achieved ratio matches the target exactly.
- An invalid or empty ratio (non-numeric, zero, negative, malformed separator) disables the Left/Right fields and shows an inline error instead of stale or nonsensical values.
- Entirely client-side; no backend involvement and no persistence — the calculator resets each page load.

**Visual reference:** [docs/mockups/ratio-calculator-reference.html](mockups/ratio-calculator-reference.html) — the floating launcher/bubble placement, field stacking, and suggestion list are authoritative there.

### 7.13 Feature M — Currency Category Filter

A left-side drawer, hidden by default, letting the user narrow the table to specific *kinds* of item — Currency, Fragments, Oils, Cards, Essences, and every other group GGG's own Item Icons catalog classifies items into ([DATA_SOURCES.md § Item Icons](DATA_SOURCES.md#item-icons)) — independent of Feature H's per-technique filter.

**Requirements:**
- Opened via a 3-line hamburger toggle in the top-left of the header; the drawer itself is hidden until opened, and closes via its own close control, an outside click, or the hamburger again.
- One row per category, ordered by how many items that catalog group has (most items first) — not alphabetical, and not the catalog's own listing order.
- Each row is a clickable **selected line** with a leading icon and the category's label — not a checkbox — that highlights when active; clicking it toggles that category on/off.
- All categories checked by default — same opt-out convention as Feature H, so the default view shows everything.
- **"Select all" / "Deselect all" controls above the list** — plain text actions, not buttons, matching the drawer's own understated visual language — bulk-set every category on or off in one click rather than requiring 23 individual clicks.
- **A row's category is determined by the last leg of its Via chain.** For every technique except Divination Card, Via has exactly one leg, so this is unambiguous. For Divination Card, Via is a two-step chain (the card, then its turn-in reward) — the category that matters is the **reward the card gives when turned in**, not the card itself (which is always the "Cards" category and thus not a meaningful filter dimension on its own).
- A purely client-side display filter over the already-fetched result set, combining with Features H and I over the same rows — same rationale as Feature H (small data volumes, keeps this entirely in the frontend layer).
- **Persisted client-side (browser storage), surviving a full page reload** — same mechanism, per-browser scope, and first-visit/corrupted-storage fallback (all categories enabled) as Features H/I (§ 7.8/7.9).

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
