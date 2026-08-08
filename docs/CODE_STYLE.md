# Code Style & Design (Elixir/Phoenix/LiveView)

**Related docs:** [ARCHITECTURE.md](ARCHITECTURE.md) (system-level resilience design) · [ELIXIR_TEST_MANIFESTO.md](ELIXIR_TEST_MANIFESTO.md) (testing discipline for this stack)

This document follows Robert C. Martin ("Uncle Bob") Clean Code / SOLID / Clean Architecture material, translated into idiomatic Elixir rather than restated generically. Where Elixir has no equivalent of an OOP concept (classes, mutable objects), that's called out explicitly rather than forced.

## Naming

- Names reveal intent — `checkpoint_next_change_id` beats `id`.
- Predicate functions end in `?` (`stale?`, `solo_self_found?`) — this is the language's own convention. This applies to *functions only* — a boolean struct field is never named with a trailing `?` (`is_current`, `predictable`, `at_tip`, not `predictable?`), both because a field access isn't a function call and because every domain struct eventually backs an Ecto schema whose field names map to DB columns, which can't contain `?`.
- A function that can raise, alongside a same-named function that returns a tagged tuple, gets a `!` suffix (`fetch_hour!/1` raises; `fetch_hour/1` returns `{:ok, result} | {:error, reason}`). The `!` version is always a thin raising wrapper around the tuple-returning one — never independent logic living only under the `!` name.
- One word per concept, project-wide: this project standardizes on `fetch_*` (outbound HTTP), `resolve_*` (computed/derived lookups), `normalize_*` (adapter raw→domain conversion).
- Module names are nouns matching their architectural role (`ExchangeSourceGateway`, `FlipOpportunity`); function names are verb phrases (`normalize_snapshot/1`, `compute_margin/2`).

## Functions

- Small, one thing, one level of abstraction per function. The Elixir tool for this: prefer multiple function clauses with pattern matching over a single function body with an internal `case`/`cond`. A function whose first thing is a large branch on its argument's shape is usually better expressed as separate clauses.
- Pipe-friendly: a function meant to be piped takes its "subject" as the first argument, so `snapshot |> normalize() |> validate()` reads top to bottom.
- No boolean flag arguments. Use a descriptive atom matched in the function head (`:strict` / `:lenient`) or two separately named functions, never a bare `true`/`false`.
- No output arguments — Elixir's immutability makes most of this moot, but the underlying principle survives: a function returns its result; it doesn't smuggle a second result out through a `Process` dictionary, an `Agent`, or ETS as a side channel.
- Command-query separation: a function either returns data or causes a side effect (send a message, write to the DB/ETS) — never both silently. Side-effecting functions are named to say so (`persist_snapshot!/1`), never disguised as a plain getter.
- `{:ok, result} | {:error, reason}` over exceptions for *expected* failure paths (see Error Handling below); `raise` is reserved for genuinely exceptional, programmer-error states.

## Comments & Documentation

- Prefer expressive code over comments: fix the code before reaching for a comment.
- Elixir separates `@doc`/`@moduledoc` (documentation — part of the public contract, expected on every public module/function in the Gateways and Contexts layers) from inline `#` comments (only non-obvious *why*, never *what*, never commented-out code, never changelog/attribution comments).
- `@moduledoc false` on internal modules that aren't part of any public API, so tooling (`mix docs`, Dialyzer) treats them correctly.

## Formatting

- `mix format` is non-negotiable and runs in CI — there's no style debate to have; the formatter *is* the rule.
- Step-down/newspaper ordering within a module: public API first, private helpers below, in call order, kept vertically close to their caller.
- [Credo](https://github.com/rrrene/credo) `--strict` in CI mechanically enforces the naming/consistency/readability rules above.

## Data

Elixir has no objects — every value already *is* a data structure (struct, map, tuple) with no attached behavior, so there's no encapsulated/exposed hybrid to guard against; the language doesn't let you bolt methods onto data in the first place.

What still applies:

- Domain structs (`%Currency{}`, `%ExchangeMarketSnapshot{}`, `%FlipOpportunity{}`, from [ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer)) are plain structs with `@enforce_keys` for required fields — no validation or business logic embedded as struct methods; validation lives in the gateway/adapter that produces the struct.
- The Law of Demeter's underlying point survives structurally: don't scatter deep field-access chains (`snapshot.market.rates.primary`) across call sites. Give the module that owns that concept a function (`ExchangeMarketSnapshot.primary_rate/1`) instead of letting every caller know the internal shape.

## SOLID → Elixir Idiom

- **Single Responsibility** — a module has one reason to change. `ExchangeIngestion` orchestrating the checkpoint walk and the adapter parsing raw GGG JSON are different modules.
- **Open/Closed** — a new external data source is a new module implementing the relevant `@behaviour`, not a new branch in an existing adapter's `case`. A new Feature (per [PRD.md](PRD.md) Features A–L) is a new context function, not a growing `cond` inside an existing one.
- **Liskov Substitution** — any module implementing `@behaviour ExchangeSourceGateway` must be swappable behind that behaviour with zero caller changes. This is also the exact seam [ELIXIR_TEST_MANIFESTO.md](ELIXIR_TEST_MANIFESTO.md) uses to wire in fixture-backed gateways under test.
- **Interface Segregation** — narrow, focused `@behaviour`s (`SnapshotReader`, `SnapshotWriter`) rather than one fat behaviour a caller only partially implements.
- **Dependency Inversion** — context/use-case modules depend on a `@behaviour`, never a concrete HTTP client module. Which concrete module satisfies the behaviour is chosen by `Application.get_env/3`, configured per Mix env (`:dev`/`:prod` → real GGG client, `:test` → fixture-backed gateway) — no mocking library needed for this swap.

## Clean Architecture / Layering, Elixir Shape

Concentric-rings Dependency Rule: nothing in an inner ring may name, import, or know about an outer ring.

- **Entities** — plain structs, as above. No `Ecto.Schema`, no `Phoenix` imports.
- **Use Cases** — plain functions in Context modules (a `FlipOpportunities` context exposing `compute_opportunities/1`). This is the **functional core**: pure input → output, no `Ecto.Repo` call, no HTTP call, no `Phoenix` reference inside these functions.
- **Gateways** — `@behaviour`s the context defines for what it needs from outside (`ExchangeSourceGateway`, `SnapshotRepositoryGateway`, `LeagueGateway`). Concrete implementations (the real GGG HTTP client, the Ecto-backed repo) live in the **imperative shell**, satisfying the behaviour from outside.
- **Controllers/Presenters, collapsed** — because this is LiveView, not a separate JSON API plus SPA, there's no separate Controller/Presenter/DTO ceremony. A LiveView module plays both roles at once, and takes over the **Humble Object** role a thin UI component plays elsewhere: `mount/3` and `handle_event/3` call into context functions, assign the result; the `.heex` template shapes it for display. No business logic in a template, no direct `Ecto.Repo` or gateway call from a LiveView module.
- **Frameworks & Drivers (outermost)** — Phoenix/LiveView itself, Ecto, the GGG HTTP client (Req/Finch), Ecto migrations. Thin and replaceable; exists only to plug into boundaries the inner rings defined.

**Humble Object rule for LiveView:** if you're tempted to write filtering/sorting/formatting logic, or a direct `Ecto.Repo`/gateway call, inside `handle_event/3` or a `.heex` template — stop. That logic belongs in a context function or a small pure formatting function next to it, not inlined in the LiveView module.

**Day-one enforcement (already in place):**

1. [`boundary`](https://github.com/sasa1977/boundary) (Saša Jurić), configured with groups matching the rings above (`Core` = entities + contexts, `Gateways`, `Web` = LiveView/Phoenix) — enforced at compile time as a `mix` compiler, not just prose. `mix compile --warnings-as-errors` turns a boundary violation into a build failure, not a local-only warning.
2. Credo `--strict`, wired into CI.

Both fail the build, not just warn locally, so the Dependency Rule and naming/consistency rules are non-negotiable.

## Error Handling

- Guiding principle: validate at the boundary, fail loudly (see [ARCHITECTURE.md § 2](ARCHITECTURE.md#2-validate-at-the-boundary-fail-loudly)).
- Idiomatic Elixir shape: gateways/adapters return `{:ok, normalized}` or `{:error, %ExchangeSchemaValidationError{...}}` — a specific, named error struct, not a bare string or generic atom — the moment raw data doesn't match the expected shape. Don't let a malformed field surface later as an unrelated `KeyError`/`FunctionClauseError` several calls downstream.
- `raise` is reserved for genuinely exceptional/programmer-error states. Expected failure modes (schema mismatch, network failure mid-walk) are values, propagated up through context functions as `{:error, reason}` and surfaced as an explicit error assign in the LiveView, rendered as a visible error state — never swallowed by a bare `rescue` that logs and continues, which is exactly the "silently wrong" failure mode [ARCHITECTURE.md](ARCHITECTURE.md) rejects.
- Every error struct carries context (which league, which change-stream hour, which field failed validation) — this is what an AI agent or maintainer sees first when a fixture-based test fails (see [ELIXIR_TEST_MANIFESTO.md](ELIXIR_TEST_MANIFESTO.md)).

## Testing

Testing discipline for this stack — integration-first, fixture-backed, no mocks at external boundaries — is significant enough to warrant its own document: see [ELIXIR_TEST_MANIFESTO.md](ELIXIR_TEST_MANIFESTO.md).

## The Boy Scout Rule

Leave code cleaner than you found it; keep drive-by cleanups small and scoped to the file already being touched.
