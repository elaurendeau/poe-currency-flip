# Instructions for AI coding agents

Before writing or modifying code in this repo, read the relevant docs first — do not rely on general knowledge or default conventions instead:

- [docs/CODE_STYLE.md](docs/CODE_STYLE.md) is required reading before any code change. It defines naming, function design, SOLID, and the Clean Architecture layering (Entities → Contexts → Gateways → LiveView, per Phoenix's own structure) this codebase follows, plus error-handling and testing discipline.
- [docs/ELIXIR_TEST_MANIFESTO.md](docs/ELIXIR_TEST_MANIFESTO.md) is required reading before writing any test. Outside-in TDD, fixture-based integration tests (no mocks at external boundaries), and the Use-Case Discovery Procedure for drilling every use case before writing its test.
- Data ingestion or anything touching external APIs (GGG, PoE Wiki): also read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) first.
- Database schema changes: also read [docs/SCHEMA.md](docs/SCHEMA.md) — new Ecto migration files only, never edits to the existing init migration.

Full doc index: [README.md](README.md).

**Enforcement:** compile-time boundary layering is already wired up via the [`boundary`](https://github.com/sasa1977/boundary) library and `mix compile --warnings-as-errors` (see [docs/CODE_STYLE.md § Clean Architecture](docs/CODE_STYLE.md#clean-architecture--layering-elixir-shape)) — a layering violation fails the build, not just a local warning. Don't let the architecture rules be prose-only; keep this enforcement in place for any new module.

## Tooling

`gh` (GitHub CLI) is not on PATH in the default Windows shell (PowerShell/Git Bash) but is authenticated and available through WSL. When a `gh` command is needed (checking/changing the GitHub default branch, PRs, issues, etc.), run it via WSL (e.g. `wsl gh ...`) rather than reporting it as unavailable.

## Branching

`main` is this repository's mainline/default branch. A `master` branch also exists in history (currently pointing at the same commit as `main`) — treat it as legacy; never create, target, or base new work off a branch literally named `master`. Feature branches are cut from `main`, and PRs target `main`.

## Regression discipline

Whenever a bug or gap is found and fixed — in this session or a future one — add a test (or, if genuinely untestable, a documented manual-verification step) that would have caught it, committed in the same change as the fix. A fix without a regression test is a fix that can silently come back.

Prefer fixture-based tests over mocks where the two compete: a saved real response from the actual external source (GGG, PoE Wiki) in, an asserted normalized/parsed output out — see [docs/ARCHITECTURE.md § Contract Tests via Fixtures](docs/ARCHITECTURE.md#3-contract-tests-via-fixtures) and [docs/ELIXIR_TEST_MANIFESTO.md](docs/ELIXIR_TEST_MANIFESTO.md). Mocking is still the right tool one layer up — for isolating a use case's own orchestration logic from the data it's fed — but the boundary adapter that actually talks to an external shape should be proven against real captured data, not a hand-shaped stand-in.

When verifying a fix, match the actual CI/production environment rather than just what's installed locally — Elixir/OTP version, OS (CI runs on Linux; local dev here is often Windows), and container vs. host all cause real behavioral differences. (Concretely: a real production bug in this project was only found once by testing against real GGG data on Render, not local tests using `DateTime.utc_now()` — see the `snapshot_hour` precision fix in git history.) Docker is available specifically to reproduce CI's environment before pushing when in doubt.

## UI layout discipline

Whenever a UI layout is added or changed, check it against **both** [docs/mockups/*.html](docs/mockups/) (open it in a browser — the rendered mockup, not just its HTML source, is the actual visual reference) and the relevant [PRD.md](docs/PRD.md) requirement section, before considering the work done. PRD.md's prose describes intent and requirements, not exact layout — when the two seem to disagree, the mockup wins on placement/structure/styling, and PRD.md wins on functional requirements (what must be shown, when, in what precision). Don't implement a UI feature from PRD prose alone without opening the mockup.

(Concretely: the Data Freshness Banner was first built as a full-width strip below the header, because that matched a literal reading of PRD.md § 7.6's wording ("a persistent banner... alongside the refresh control") without checking back against docs/mockups/flip-row-reference.html, which places the timestamp centered in the header itself with no separate strip and no label prefix. Had to be redone as a follow-up once the user pointed out the mismatch.)

When a mockup doesn't yet cover a new element (e.g. a second, distinctly-labeled refresh action didn't exist in the mockup before the ingestion-refresh feature), update the mockup itself in the same change, not just the real component. A mockup that's drifted out of sync with the actual UI stops being a reliable reference for the next change.
