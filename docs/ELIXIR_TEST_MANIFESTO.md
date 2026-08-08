# Test Manifesto (Elixir/Phoenix/LiveView) — Proposed Migration Target

**Related docs:** [ELIXIR_CODE_STYLE.md](ELIXIR_CODE_STYLE.md) (code style/design this testing discipline pairs with) · [ARCHITECTURE.md § 3 Contract Tests via Fixtures](ARCHITECTURE.md#3-contract-tests-via-fixtures) (the principle this document generalizes) · [CODE_STYLE.md § Testing](CODE_STYLE.md#testing) / [FRONTEND_CODE_STYLE.md § Testing](FRONTEND_CODE_STYLE.md#testing) (what this replaces)

**Status:** governs Elixir/Phoenix/LiveView tests *if and when* this codebase migrates to that stack. Does not apply to the current Java/React test suites.

## Guiding Principle: Integration Is the Default, Not the Exception

Every test that exercises code crossing a boundary — a LiveView event handler, a context function calling a gateway, an ingestion checkpoint walk — is written as an **integration test that runs the real path end to end**, not an isolated unit test with mocked collaborators standing in for real ones.

This isn't just a preference carried over from the Java/React docs — it's a better fit for what LiveView actually is. In the current stack, a Java backend and a React frontend are two separate processes, so [CODE_STYLE.md](CODE_STYLE.md#testing) and [FRONTEND_CODE_STYLE.md](FRONTEND_CODE_STYLE.md#testing) each define their own fixture-contract-test layer, tested independently, with a JSON DTO boundary in between. LiveView collapses that into one process: there is no separate JSON API to contract-test apart from the UI it feeds. Mounting a LiveView and driving a real user interaction already exercises gateway → normalization → context computation → rendered HTML in one pass. Splitting that back into artificial unit layers with mocked collaborators would recreate the exact two-process indirection this migration removes.

**The one deliberate carve-out:** pure, stateless functional-core functions — ratio/margin math, a sort comparator, a currency-display formatter — still get a plain, fast `ExUnit` unit test with no I/O (see "What Still Gets a Plain Unit Test" below). Wrapping trivial pure-function math in a full LiveView mount just to call it "integration" is indirection for its own sake, not rigor. Everything that touches a gateway, the database, or an external response shape does not get this exemption.

## TDD Workflow: Outside-In, Red-Green-Refactor

Integration-by-default doesn't mean abandoning TDD — it changes the *shape* of the first test, not whether one is written first. The standard cycle from [CODE_STYLE.md § Testing](CODE_STYLE.md#testing) still applies: **Red** (write a failing test expressing the desired behavior) → **Green** (write the minimum code to pass it) → **Refactor** (clean up now that a passing test locks the behavior in place).

- Because integration is the default, the outermost Red test is usually a `Phoenix.LiveViewTest` test (or, for a flow with no UI yet, a context-level integration test against a fixture/Bypass-backed gateway) — not a narrow unit test built against a mock for an interface that doesn't exist yet. This is **outside-in TDD**: start from user-observable behavior (a rendered table row, a computed flip opportunity appearing on screen), let that failing test drive what context functions and gateway calls need to exist, and only drop to a plain unit test for a piece of pure functional-core logic once the outside test surfaces a genuinely isolated computation worth pinning down on its own — e.g. once the LiveView test demands a margin calculation, write a focused unit test for `compute_margin/2` itself alongside implementing it, per "What Still Gets a Plain Unit Test" below.
- Minimum code to pass, every step. Resist writing more than the current failing test demands even when the fuller implementation is obvious — this is what keeps outside-in TDD from silently degrading into "build the whole feature, then backfill tests," which defeats the point of the tight feedback loop.
- A red integration test must fail for the *right* reason (missing behavior) — not an unrelated setup error (a fixture file typo, an unconfigured Bypass route). Inspect the first failure before treating it as the expected "red"; a wrong-reason failure that happens to also be red is not a valid starting point for Green.

## Use-Case Discovery — Drill First, PRD-Trace, Then Test

Outside-in TDD (above) assumes the failing test you're about to write already captures the right behavior. It usually doesn't, on the first pass — the golden path is obvious, but the edge cases, error paths, and state-dependent variations that actually make software correct are easy to miss unless you deliberately go looking for them before writing anything. This is the step that happens *before* Red:

1. **Drill for every use case the behavior at hand must satisfy** — not just the golden path. For each context function, gateway, or LiveView interaction, enumerate: the happy path(s); boundary/edge conditions (empty results, zero values, exact ties, threshold cutoffs); error/failure paths (upstream schema mismatch, network failure, the GGG tip/404 sentinel); state-dependent variations (first run vs. an established checkpoint, no leagues yet, no favorites yet, a league switch mid-session); and cross-feature interactions (an ingestion refresh completing re-triggers flip recomputation; changing league resets other filters). When porting existing behavior, the Java interactor source and its tests are primary source material — they already encode most of these decisions (e.g. `docs/PRD.md` § 7.2 already documents micro-rules like "zero-volume opportunities dropped entirely" and "a buy side that can't sustain a -1 undercut is dropped"). Port the *decisions*, not just the happy-path shape, and deliberately interrogate every input for "what if this is empty/zero/missing/stale."
2. **Every discovered use case is written into `docs/PRD.md` before its test is written** — a bullet under the relevant Feature section (§ 7.1–7.12), matching the granularity already established there. If a use case doesn't fit an existing Feature section, that's a signal a bullet — or occasionally a new Non-Goal — needs to be added explicitly, not left implicit in code or in a chat transcript. This makes the PRD the exhaustive spec of every use case the app handles, not just a feature-level overview: a use case that exists only as a test with no PRD entry, or a PRD line with no covering test, is a gap to close, not something to leave be.
3. **Only then does outside-in TDD begin** (per the section above): one failing test per enumerated use case, red → green → refactor.

This loop applies to every context function, gateway, and LiveView interaction built during the migration — it is not optional rigor reserved for the trickiest logic. The point of writing it down here is that the discipline survives across sessions: a future session (or a different AI agent) picking this codebase back up should find this loop already documented, not have to re-derive it from a conversation it wasn't part of.

## No Mocks at the Boundary — Real Fixtures Are the Test Double

This is the concrete rule this document exists to state: **when the app would normally call an external API, the test environment returns real, committed response files — never a mocking library standing in with hand-built data.**

- Every external source this app calls (GGG Currency Exchange API, GGG leagues endpoint, PoE Wiki) has its real, captured responses committed under `test/fixtures/<source>/<scenario>.json` — e.g. `test/fixtures/ggg_exchange/single_hour_page.json`, `test/fixtures/ggg_exchange/tip_404.json`, `test/fixtures/ggg_leagues/current_leagues.json`, `test/fixtures/poe_wiki/vendor_recipes.json`. Each fixture is a byte-for-byte real response, not hand-written JSON approximating one — the same discipline [ARCHITECTURE.md § 3](ARCHITECTURE.md#3-contract-tests-via-fixtures) already requires for adapter contract tests, generalized to be the default for every test that would otherwise call out to a live source.
- **No mocking library (e.g. Mox) stands in for an external HTTP call.** Two mechanisms accomplish this, depending on what the test needs to prove:
  1. **Preferred — [Bypass](https://github.com/PSPDFKit-labs/bypass):** a local HTTP server started in the test, serving a fixture file's raw bytes as the response body. This exercises the *real* HTTP client (Req/Finch) code path, not just the parsing logic downstream of it — a regression in headers, timeouts, or client config would actually be caught, which the behaviour-swap approach below would miss.
  2. **Where transport specifics don't matter** (e.g. a context-level test focused on orchestration, not HTTP): swap the `@behaviour` implementation via `Application.put_env/3` in `:test` to a `Fixture<Source>Gateway` module. That module still reads the real committed JSON file and runs it through the *actual* production normalization/parsing code — the only thing faked is the network hop; decoding, validation, and normalization all execute for real.
- Either mechanism follows the same rule already stated project-wide in [CLAUDE.md](../CLAUDE.md): "a saved real response from the actual external source... in, an asserted normalized/parsed output out." Mocking remains the right tool one layer up — isolating a LiveView's own event-handling logic from a context it calls — never for the boundary adapter that talks to GGG or the Wiki itself.

## Fixture Governance

- **Location:** `test/fixtures/<source>/`, one file per meaningfully distinct scenario — a normal hour page, the tip/404 stop-condition response, a malformed/edge-case response used to exercise the "fail loudly" error path.
- **Provenance:** each fixture is accompanied by a one-line note (sibling `.meta` file or leading comment where the format allows) recording the source URL and capture date, so staleness is checkable at a glance.
- **Refresh discipline:** when a GGG/Wiki shape is suspected to have changed, or periodically regardless, fixtures are re-captured from the live source and committed fresh. A fixture test failing right after a refresh is the intended, ideal failure mode per [ARCHITECTURE.md § 3](ARCHITECTURE.md#3-contract-tests-via-fixtures): specific, scoped to one gateway/adapter, obvious what changed — not a vague downstream symptom in an unrelated feature test.

## LiveView Integration Tests

- Written with `Phoenix.LiveViewTest`: `live/2` to mount, `render_click/2` / `render_change/2` / `render_submit/2` to simulate real user interaction, asserting against rendered HTML (`render/1`, `has_element?/2`) — not against internal `assigns` state directly, except where no rendered element expresses the state being checked.
- A test for, say, the flip-opportunity table mounts the LiveView with the real Bypass-served or fixture-backed GGG response wired in for `:test`, drives the actual league-selector interaction, and asserts on the rendered table rows — proving the full slice (gateway → normalization → context computation → LiveView assigns → rendered HTML) in one test. Today this is two separate suites (ingestion/Feature logic per [ARCHITECTURE.md](ARCHITECTURE.md), component rendering per [FRONTEND_CODE_STYLE.md](FRONTEND_CODE_STYLE.md)); under LiveView it's one.
- Tests are written from the user's point of view — what's clicked, what's typed, what appears — not as an internal-state assertion a developer would write but a real user would never observe.

## What Still Gets a Plain Unit Test

- Pure functional-core functions with no I/O and no gateway dependency: margin/ratio computation, sort comparators, currency-display formatting. Fast, isolated `ExUnit` tests, real inputs/outputs, no fixtures needed — there's no boundary to cross.
- This is a narrow exception, not a fallback. If a function needs a gateway, the database, or a fixture to exercise meaningfully, it gets an integration test — not a unit test with a mocked collaborator plugged in to avoid the "expense" of integration.

## FIRST, Carried Over

Same principles as [CODE_STYLE.md § Testing](CODE_STYLE.md#testing), holding even though the default here is integration-scoped:

- **Fast** — fixtures are local files; Bypass is a local server. No test ever makes a real network call to GGG or the Wiki.
- **Independent** — each test sets up its own fixture-backed gateway or Bypass instance; DB-touching tests use the Ecto Sandbox so no mutable state leaks between tests.
- **Repeatable** — no reliance on live GGG/Wiki state or timing; a committed fixture file is deterministic.
- **Self-validating** — pass/fail on rendered HTML or returned structs, no manual log inspection.
- **Timely** — written alongside the code, not after.

## CI Enforcement

- `mix test` runs with no real network access needed in the `:test` env — every boundary call is fixture- or Bypass-backed by design, so an accidental live call from a test is a bug in the test itself, not a flaky-test tolerance issue to work around.
- A stale fixture (GGG/Wiki actually changed shape) surfaces as a specific, scoped CI failure pointing at one gateway/adapter — never as a vague downstream symptom in an unrelated feature test. This is the same "ideal shape of problem to hand to an AI coding agent" [ARCHITECTURE.md § 3](ARCHITECTURE.md#3-contract-tests-via-fixtures) already calls out for the current stack.
