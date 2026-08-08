# Tech Stack

**Related docs:** [PRD.md](PRD.md) (what we're building) · [ARCHITECTURE.md](ARCHITECTURE.md) (how we isolate ourselves from external sources) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external API contracts) · [SCHEMA.md](SCHEMA.md) (database schema) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

## Decision: server-rendered, not a separate API + client-side app

The Currency Exchange API ([DATA_SOURCES.md](DATA_SOURCES.md)) sends no `Access-Control-Allow-Origin` header, so browsers block calling it directly from client-side JavaScript — verified by direct testing. A pure client-side app cannot ingest this data; all Currency Exchange ingestion, adapters, validation, and flip-margin computation ([ARCHITECTURE.md](ARCHITECTURE.md)) must run server-side.

This app is Phoenix LiveView: one Elixir process serves both the computation and the UI over a persistent connection, pushing rendered HTML diffs to the browser as state changes — no separate JSON API, no separate single-page-app build, no REST/GraphQL contract to keep in sync between two codebases. (The Leagues API does allow direct browser calls (`Access-Control-Allow-Origin: *`), but the server owns it anyway for consistency — there's only one place that talks to GGG at all.)

## Stack

| Layer | Choice | Why |
|---|---|---|
| Application | Elixir 1.18 + Phoenix 1.7 + LiveView 1.0 | Owns ingestion/adapters/validation/computation and the UI in one process — see [CODE_STYLE.md](CODE_STYLE.md) for how Clean Architecture layering maps onto Phoenix Contexts + the `boundary` library. |
| Database | PostgreSQL (via Ecto) | Stores the Currency Exchange ingestion checkpoint and normalized market state between runs, plus vendor recipe / divination card reference data. |
| Schema migrations | Ecto Migrator | Versioned migration files under `app/priv/repo/migrations/` are the only source of truth for the schema. Every schema change is a new migration file, applied in order, tracked in Ecto's own `schema_migrations` table. See [SCHEMA.md](SCHEMA.md). |
| Communication | None — server-rendered | LiveView pushes diffs over a persistent WebSocket (falling back to long-polling); no REST/GraphQL API, no client-side data-fetching layer to keep in sync with a separate backend. |

## Hosting (free tier)

| Component | Where | Notes |
|---|---|---|
| Application | [Render.com](https://render.com) free web service (Docker) | Git-push deploys via CI, zero server maintenance. **Tradeoff:** spins down after ~15 min idle; next request pays a cold-start cost (BEAM VM boot time, roughly 20-60s) before responding. Given this app is refreshed manually and used occasionally rather than continuously, it will likely be asleep on most visits — accepted as a real but tolerable UX cost in exchange for $0 hosting and no ops work. See [DEPLOYMENT.md](DEPLOYMENT.md) for the Docker release and migrate-on-deploy setup. |
| Database | [Neon.tech](https://neon.tech) free Postgres | Serverless Postgres, free tier does not expire (unlike some other providers' free databases). Also scale-to-zero, consistent with the low-traffic usage pattern. Requires SSL (`ssl: true` in the Ecto config) — Neon rejects plaintext connections outright. |

Alternative considered and rejected for now: self-hosting on Oracle Cloud's "Always Free" ARM VM (genuinely free forever, no cold starts, but requires the owner to personally handle OS updates, uptime, backups, and TLS — real ongoing ops burden not worth it for this project's traffic level).

## UI Style

**Direction:** dark trading-terminal aesthetic — dark neutral background, gold/amber accent for margins and key numbers, monospace for numeric columns (rates, volumes), dense row-based layout optimized for scanning many flip opportunities quickly. Closer to poe.ninja or a trading dashboard than a typical light SaaS product.

**Icons, two distinct kinds per row:**
- **Item icons** — the actual currency/card art for each item in the flip (e.g. Portal Scroll, Scroll of Wisdom), sourced per [DATA_SOURCES.md § Item Icons](DATA_SOURCES.md#item-icons).
- **Flip-type icon** — a small leading icon on the left of each row identifying which mechanic produced that opportunity, so a mixed results list stays scannable at a glance without reading each row's text. Distinct icon per [PRD.md](PRD.md) feature: 7.1 vendor recipe, 7.2 exchange spread, 7.3 divination card, 7.5 Bulk Buy (triangular arbitrage).

**Currency ordering convention:** every flip row displays currencies left-to-right starting from the currency the player already holds, ending with what they receive — never the reverse. For a round-trip flip (Feature A/C, where you end up with more of the currency you started with), lead with that starting currency rather than the intermediate item. For a multi-hop flip (Feature E), order strictly follows the trade sequence (e.g. Divine → Stacked Deck → Chaos, not Stacked Deck → Divine → Chaos).

**Data freshness banner** (implements [PRD.md § 7.6 Feature F](PRD.md#76-feature-f--data-freshness-banner)): a persistent, always-visible bar at the top of the page, separate from the league selector. Displays the exact moment the active data generation was refreshed — full date, hour, minute, and millisecond, e.g. `2026-08-05 14:32:07.418` — not a relative "X minutes ago" string. Sourced directly from `active_generation_refreshed_at` ([SCHEMA.md](SCHEMA.md)).

**Reference implementation:** [docs/mockups/flip-row-reference.html](mockups/flip-row-reference.html) is a working (non-framework) HTML/CSS mockup showing the settled row design for all four flip-finding features. Open it directly in a browser — it hotlinks real icons from GGG's trade API ([DATA_SOURCES.md § Item Icons](DATA_SOURCES.md#item-icons)) so the actual visual result is inspectable, not just described. When implementing the results table/row component, match this reference rather than reinterpreting the prose below.

**Row structure — six columns**, in this fixed order:

1. **Start** — icon + quantity of the currency the player begins with, name below (e.g. "1 [chaos icon] Chaos").
2. **Via** — the intermediate step(s): one or more `quantity + icon + name` groups chained with arrows, representing every hop in the flip (e.g. `86 [icon] Transmutation → 344 [icon] Wisdom → 114 [icon] Portal`). A muted subtitle line below gives mechanic-specific detail that doesn't fit as an icon (e.g. "vendor + recipe chain", "instant 185:1c · competitive 366:1c", "direct rate 210c" for comparison in Feature E, "≈1.8c per card" for Feature C).
3. **Sell** — icon + quantity of the currency received at the end, same format as Start.
4. **Margin** — percentage return, monospace, color-coded (green for strong margins, amber for smaller ones — same thresholds as Profit).
5. **Profit** — absolute return in Chaos, shown as `+N` next to a small Chaos icon (not a bare "c" suffix), same color coding as Margin.
6. **Volume** — how much of the opportunity is available at the given rate, muted gray, monospace.

**Colors:**
- Quantities (the numbers next to every icon): white/near-white (`#f2f4f6`), bold — distinct from item names but not tied to the amber accent, which is reserved for Margin/Profit.
- Item and currency names: light gray (`#d8dde2`).
- Subtitle detail line: muted gray (`#6b7480`), monospace, smaller.
- Margin/Profit: green (`#5fd07a`) above a "strong" threshold, amber (`#e8a33d`) otherwise — exact threshold TBD when real data ranges are known.
- Arrows between hops: muted (`#525a63`), never the accent color.

**Icons, two distinct kinds per row:**
- **Item icons** — real currency/card art sourced per [DATA_SOURCES.md § Item Icons](DATA_SOURCES.md#item-icons), used in Start/Via/Sell.
- **Generic type icon** — used only where no real per-item art exists (currently: divination cards, since GGG's API exposes no card icon field — see [DATA_SOURCES.md](DATA_SOURCES.md)). Rendered visually distinct (a card-suit glyph in purple) so it's never mistaken for real item art.

**Filter bar** (implements [PRD.md § 7.8 Feature H](PRD.md#78-feature-h--technique-filters)): a row of checkboxes above the table header, one per technique, all checked by default. Unchecking one hides that technique's rows immediately — client-side only, no re-fetch.

**Sortable/filterable columns** (implements [PRD.md § 7.9 Feature I](PRD.md#79-feature-i--column-sorting--threshold-filters)): the Margin, Profit, and Volume column headers are clickable to sort, with a small directional arrow indicating the active sort column/direction. Each of those three headers also carries a small threshold-filter control (a numeric input, e.g. "min volume") — visually secondary to the sort click target so the two don't compete for the same click.

**Favorites** (implements [PRD.md § 7.10 Feature J](PRD.md#710-feature-j--favorites)):
- Right-click a row → context menu with a single "Favorite" / "Unfavorite" toggle.
- Favorited rows render as a distinct group above the main table, separated by a visible divider, not just sorted to the top of one continuous list — the two groups should read as clearly different at a glance.
- Row styling: a subtly different background (a faint amber-tinted wash, not a strong color that would clash with the margin/profit color coding) plus a small filled star icon in the leftmost position of the row, ahead of the Start column.

## Credential Policy

No API in current use requires authentication (see [DATA_SOURCES.md](DATA_SOURCES.md) — Currency Exchange and Leagues are both public, no-auth). This section is a standing principle for if that ever changes:

**The app must never hold or use a single shared API key/credential on behalf of all users.** If a future feature requires an authenticated GGG endpoint (e.g. account-scoped data), each user supplies and stores their own credential; the backend uses only the requesting user's credential for that user's requests. This avoids one user's usage exhausting a shared quota or getting a shared key rate-limited or revoked for everyone.
