# Database Schema

**Related docs:** [PRD.md](PRD.md) (what we're building) · [ARCHITECTURE.md](ARCHITECTURE.md) (resilience principles this schema follows) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external API contracts this schema normalizes) · [TECH_STACK.md](TECH_STACK.md) (Postgres via Spring Data JPA) · [CODE_STYLE.md](CODE_STYLE.md) (Java code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

This is the internal domain model referenced in [ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer) — the only shape the rest of the application ever sees. External API responses are normalized into these tables at the adapter boundary; nothing outside the adapters touches raw GGG/wiki shapes.

**This document is the rationale; [db/migration/V1__init_schema.sql](../db/migration/V1__init_schema.sql) is the actual executable schema.** The two must stay in sync — if you change one, change the other. Schema changes going forward are new Flyway migration files (`V2__...`, `V3__...`), never edits to `V1`, and never Hibernate auto-ddl (see [TECH_STACK.md](TECH_STACK.md)).

## Reference data (static, seeded once, updated rarely)

```
currency
  id                 PK
  external_id        unique — GGG's raw item path (e.g. "Metadata/Items/Currency/CurrencyPortal")
  display_name       e.g. "Portal Scroll"
  icon_url           from DATA_SOURCES.md § Item Icons
  item_type          enum: CURRENCY | DIVINATION_CARD

vendor_recipe
  id                 PK
  input_currency_id  FK -> currency
  input_quantity
  output_currency_id FK -> currency
  output_quantity
```

A single table covers both plain vendor sell-rates and multi-item recipes — a plain "sell Scroll of Wisdom to vendor" rate is just a row with `input_quantity = 1`, no separate table needed. Sourced from the PoE Wiki per [DATA_SOURCES.md § Vendor Sell Rates & Recipes](DATA_SOURCES.md#vendor-sell-rates--recipes); captured manually given the wiki's anti-bot protection, not scraped automatically.

```
divination_card
  currency_id        FK -> currency (PK)
  stack_size         cards needed for a full set
  reward_currency_id FK -> currency, nullable
  reward_quantity
  is_predictable     boolean
```

`is_predictable = false` for gamble/random-reward cards excluded from [PRD.md § 7.3](PRD.md#73-feature-c--divination-card-flip-finder). These rows are kept, not omitted, so the exclusion decision stays visible and auditable rather than silently absent from the data.

## League cache

```
league
  id                    PK
  external_id           unique — GGG's league id, e.g. "Allflame"
  display_name
  is_current            from category.current
  has_exchange_activity boolean
```

Refreshed from the live Leagues API ([DATA_SOURCES.md § League List](DATA_SOURCES.md#league-list)), not hand-maintained. `has_exchange_activity` is set once ingestion actually observes market data for that league — this is the real gate in [ARCHITECTURE.md § League Resolution](ARCHITECTURE.md#league-resolution) (step 3), stronger than the SSF rule-filter alone.

## Ingestion state and market data

No history is kept at all — only ever one live working set, replaced wholesale on each refresh via a **hot-swap**: new data is written under a new generation tag while the old generation keeps serving reads, then a single atomic pointer flip makes the new generation live, and the old generation is deleted.

```
exchange_ingestion_state
  id                        PK, singleton row (PC only — no other platform is in scope, see PRD.md Non-Goals)
  last_processed_change_id  the next_change_id cursor to resume walking from, per DATA_SOURCES.md
  active_generation_id      which generation in exchange_market_snapshot is currently live (what every query reads)
  active_generation_refreshed_at   when the active generation was activated — feeds the staleness display in PRD.md § 8
  updated_at

exchange_market_snapshot
  id                 PK
  generation_id      which ingestion batch this row belongs to (not yet necessarily active)
  league_id          FK -> league
  currency_a_id      FK -> currency
  currency_b_id      FK -> currency
  snapshot_hour      the most recent hour this pair showed activity during the walk that built this generation
  volume_traded_a, volume_traded_b
  lowest_stock_a, highest_stock_a
  lowest_stock_b, highest_stock_b
  lowest_ratio_a, highest_ratio_a
  lowest_ratio_b, highest_ratio_b
  unique (generation_id, league_id, currency_a_id, currency_b_id)
```

**Why a generation tag instead of a single un-tagged table with delete-then-insert:** the multi-hour catch-up walk makes external HTTP calls interleaved with database writes, which can take a while and shouldn't sit inside one long-lived DB transaction (connection/lock lifetime risk). Tagging is what lets the slow, external-API-driven work happen with no open transaction at all, and reduces the "made live" moment to a single fast, atomic update.

**Refresh flow:**
1. Read `last_processed_change_id` and mint a new `generation_id`.
2. Walk forward hour by hour, writing normalized rows tagged with the new `generation_id` as each hour is validated (per [ARCHITECTURE.md § Validate at the Boundary, Fail Loudly](ARCHITECTURE.md#2-validate-at-the-boundary-fail-loudly)). Existing readers are unaffected — they're still reading the old, still-active generation.
3. Once the walk reaches the current hour successfully, in one short transaction: update `last_processed_change_id`, flip `active_generation_id` to the new generation, set `active_generation_refreshed_at` to now, and delete every row belonging to the now-superseded generation. This single transaction is the only moment "new" data becomes visible to the app, and it's also the entire purge mechanism — the table never holds more than one generation's worth of rows once the transaction commits.
4. If the walk fails at any point, stop: `active_generation_id` never moves, the old data keeps serving untouched, and the partially-written new-generation rows are discarded (deleted, since they never became active). This is [ARCHITECTURE.md § Failure Handling](ARCHITECTURE.md#failure-handling)'s "no partial/corrupt state is persisted" rule, implemented concretely.

**No scheduled cleanup job needed.** The tables here are small — a few hundred to a few thousand rows per refresh, based on direct testing of the source API — so folding the purge into the same transaction as the pointer flip is simple and fast enough on its own; there's no case where a background job would help. Postgres's own autovacuum reclaims the physical disk space freed by the `DELETE` automatically (a `DELETE` marks rows dead under MVCC rather than instantly freeing space) — this needs no manual `VACUUM` management unless it becomes an actual measured problem later, which is unlikely given how infrequently a manual refresh runs.

No retention window, no trend history — consistent with [PRD.md § 9](PRD.md#9-future-considerations) explicitly ruling out historical charts for now. If that changes later, it's a deliberate future migration, not something this schema accidentally already half-supports.

## Deliberately not a table: flip opportunities

Features A, B, C, and E's results (the ranked lists shown to the user) are **computed on demand** from the tables above at request time, not persisted. The manual-refresh model ([ARCHITECTURE.md § Currency Exchange Ingestion](ARCHITECTURE.md#currency-exchange-ingestion-change-stream--checkpoint-model)) means there's no live feed to cache against, and storing computed results would introduce a staleness/invalidation problem the architecture's failure-handling principles are explicitly designed to avoid. This computation lives in the Java service layer, reading from `exchange_market_snapshot`, `vendor_recipe`, `divination_card`, and `currency`.
