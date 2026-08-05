# PRD: PoE Currency Exchange Flip Finder

**Owner:** tapoox
**Last updated:** 2026-08-05

**Related docs:** [ARCHITECTURE.md](ARCHITECTURE.md) (resilience & system design) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external API contracts) · [TECH_STACK.md](TECH_STACK.md) (technology decisions)

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
| **Gold** | Resource consumed to place/fill orders on the Currency Exchange; earned by selling items to vendors. |
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
- For each path, compute: buy cost (Exchange), intermediate vendor output, final recipe output, resale value (Exchange), net margin, and gold cost.
- Rank/sort by margin %, absolute profit, volume available at the buy rate, and gold cost.
- Show the full step-by-step recipe (what to buy, what to vendor, what recipe to apply, what to sell) so the user can execute it manually.

### 7.2 Feature B — Exchange Spread/Margin Finder

For each currency pair on the Exchange, compare the instant-fill rate against the competitive (limit-order) rate and surface the spread as a flip opportunity.

**Example:** Scroll of Wisdom instant sell is 185:1 Chaos; competitive rate is 366:1 Chaos. Buying in at the competitive rate (accepting slower fill) nearly doubles the yield vs. instant.

**Requirements:**
- Pull both instant and competitive/order-book rates per currency pair.
- Compute margin between the two.
- Sortable by margin, volume (depth available at the competitive rate), and gold cost.
- Since competitive-rate fills are slower and not guaranteed, flag this tradeoff clearly in the UI (e.g., a "fill speed" caveat or badge) rather than presenting it as equivalent to an instant flip.

> **Data availability note:** the public Currency Exchange API does not expose a live order book (see [DATA_SOURCES.md](DATA_SOURCES.md)) — only an hourly range of rates that actually filled (`lowest_ratio`/`highest_ratio`). This feature will be built against that hourly range as a proxy for the instant-vs-competitive spread, refreshed on demand rather than live.

### 7.3 Feature C — Divination Card Flip Finder

Finds divination cards that can be bought (as a full stack) via the Currency Exchange, turned in, and sold back for a **predictable** profit.

**Requirements:**
- Only include cards whose turn-in reward is a **fixed currency amount** — explicitly exclude gamble-style cards (random unique/item rewards, chance-outcome cards like The Void, item-conversion cards, etc.).
- Compute: cost to buy a full stack via the Exchange, reward received, resale value of that reward via the Exchange, net margin, and gold cost.
- Sortable by margin, absolute profit, volume/availability of the card stack on the Exchange, and gold cost.

### 7.4 Feature D — League Selector

A dropdown in the site settings (top right of the page) that scopes all three views (Features A–C) to a single league. Selecting a league is global to the session, not per-view.

**Requirements:**
- The league list must be fully dynamic — no hardcoded league names or IDs anywhere in the code. When GGG launches a new challenge league, it must appear in the dropdown automatically, without a code change or deploy.
- The list must only include leagues that actually have Currency Exchange activity. Leagues that don't support trading (Solo Self-Found variants) must never appear, since flip-finding is meaningless there.
- Default selection is the current mainline challenge league (not Standard).

**How this is derived:** see [ARCHITECTURE.md § League Resolution](ARCHITECTURE.md#league-resolution) for the exact algorithm, and [DATA_SOURCES.md § League List](DATA_SOURCES.md#league-list) for the verified API facts backing it.

## 8. Success Criteria

- The three views each return correct, sortable results that match manual in-game verification for a sample of flips.
- Data staleness is visible to the user (e.g., "prices as of X minutes ago").
- The tool gets used before/during play sessions to find real flips.

## 9. Future Considerations

- Alerts/watchlists: notify when a specific flip crosses a profitability threshold.
- Historical margin tracking / trend charts.
- League-start-specific views (early-league inefficiencies tend to be larger).
- PoE2 support, if/when its economy stabilizes and exposes similar mechanics.

## 10. Open Questions

1. Gold: is it worth modeling as a hard constraint (user has limited gold) or just informational for sorting?
