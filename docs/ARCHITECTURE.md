# Architecture & Resilience

**Related docs:** [PRD.md](PRD.md) (what we're building) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external API contracts) · [TECH_STACK.md](TECH_STACK.md) (technology decisions)

This document defines *how* the system is built so it stays resilient to changes in upstream data sources GGG and PoE Wiki don't guarantee to keep stable. **Any AI coding agent implementing or modifying data-ingestion code should read this document — and [DATA_SOURCES.md](DATA_SOURCES.md) — before writing code.**

## Guiding Principle: Isolate What We Don't Control

We depend on external sources (GGG's public APIs, the PoE Wiki) whose shape and behavior can change without notice. The goal is: when they change, exactly one small, well-tested part of the codebase needs to change — not features, not the database schema, not the UI.

### 1. Anti-Corruption Layer

Every external data source gets its own **adapter**: a module whose only job is converting that source's raw shape into our own internal domain model. Nothing outside the adapter ever sees the raw external shape — features, storage, and UI all work exclusively off internal types.

- Internal domain concepts (technology-agnostic, defined here so they stay stable even as adapters change): `Currency` (a tradeable item, identified by our own stable internal ID, not GGG's raw metadata path), `League`, `ExchangeMarketSnapshot` (a currency pair's rate/volume data for a point in time), `VendorRecipe`, `DivinationCardReward`, `FlipOpportunity` (the computed result feeding Features A–C).
- If GGG renames a field, changes an ID scheme, or restructures a response, only the adapter that produces that domain type changes. The domain model, the features, and the storage schema do not.

### 2. Validate at the Boundary, Fail Loudly

Every adapter validates the raw response against an explicit expected schema **before** normalizing it. If the shape doesn't match:

- The ingestion run fails immediately and visibly (a clear error surfaced to the user/builder), rather than silently producing subtly-wrong normalized data.
- Previously-good stored data is left untouched — a failed refresh must never overwrite last-known-good data with partial or malformed results.

Silent bad data (e.g., a misparsed ratio quietly producing wrong margins) is strictly worse than a visible failure. Optimize for failures being loud and immediate, not for the system always appearing to work.

### 3. Contract Tests via Fixtures

Each adapter is tested against a **saved real sample response** (a fixture file) from its external source, committed to the repo. The adapter test asserts the normalized output for that fixture.

- When GGG changes their API shape, this test breaks immediately and specifically — pointing at exactly which adapter and which field, not a vague downstream symptom.
- This is the ideal shape of problem to hand to an AI coding agent: a failing test with a concrete expected-vs-actual diff, scoped to one file. Update the fixture with a fresh real response, update the adapter, done.
- Fixtures should be refreshed periodically (or when a source is suspected to have changed) even if nothing looks broken, to catch silent drift.

### 4. Centralized Reference Data

External IDs (e.g., GGG's `Metadata/Items/Currency/CurrencyPortal`) are mapped to our internal `Currency` identifiers in exactly one place — a reference/lookup table, not scattered as magic strings across features. Vendor recipes and divination card classifications (see [PRD.md § 7.1, 7.3](PRD.md)) live in this same kind of single-source reference data, since they come from the Wiki rather than an API and must be maintained by hand.

## Data Ingestion Architecture

### Currency Exchange Ingestion (Change-Stream / Checkpoint Model)

The Currency Exchange API (see [DATA_SOURCES.md](DATA_SOURCES.md)) is a sequential change-stream, not a query-by-current-state API: each call returns one hour of market activity plus a pointer to the next hour, and arbitrary jumps are not possible.

Ingestion model:
1. Persist a checkpoint — the last successfully processed `next_change_id` — per realm.
2. On a manual "refresh" action, walk forward from the stored checkpoint, one hour at a time, until reaching the current hour, normalizing and merging each hour's markets into current state via the adapter.
3. Advance the stored checkpoint only after a batch of hours has been validated and normalized successfully.
4. Refresh does bounded work proportional to elapsed time since the last refresh, not to total time since Currency Exchange launched — no standing background poller is required (see [PRD.md](PRD.md), Feature B/manual refresh model).

### League Resolution

Implements [PRD.md § 7.4 Feature D](PRD.md#74-feature-d--league-selector). No league name or ID is ever hardcoded; the selectable list is derived at runtime:

1. Fetch the live league list from GGG's public leagues endpoint.
2. Filter out any league whose rules mark it Solo Self-Found (no trading → no Currency Exchange).
3. Cross-check remaining candidates against leagues actually observed in ingested Currency Exchange data — the authoritative signal for "supported by the Currency Exchange," catching cases rule-filtering alone would miss (e.g., a new league where the Exchange isn't enabled yet).
4. Select the league flagged as the current challenge league category as the default.

This entire algorithm lives in one place (the league-resolution adapter/service), so a change in how GGG flags leagues (new rule ids, new category shape) is a one-file fix.

## Failure Handling

- Ingestion failures (schema validation, network errors, unexpected 404s mid-walk) must surface a clear, specific error state to the user — not a blank/stale UI with no explanation.
- The UI always shows data staleness (timestamp of last successful refresh) so a failed or partial refresh is visible rather than silently trusted.
- Partial ingestion (e.g., failure on hour N of a multi-hour catch-up walk) commits nothing past the last fully-validated hour — no partial/corrupt state is persisted.

## Credential Handling

No external data source currently in use requires authentication (see [DATA_SOURCES.md](DATA_SOURCES.md)). This is a standing principle for if that changes:

**Never hold or use a single shared API key/credential on behalf of all users.** If a future feature needs an authenticated external API, each user supplies and stores their own credential, and the backend uses only the requesting user's credential for that user's own requests — never a credential owned by the app itself applied across all users. This keeps one user's usage from exhausting a shared quota or getting a shared credential rate-limited or revoked for everyone.

## Open Questions

1. Is there a reasonable cap on how many hours a single manual refresh will walk before it just serves what's currently stored and reports "partially caught up"? (Relevant if the app hasn't been refreshed in a long time — e.g., days.)
