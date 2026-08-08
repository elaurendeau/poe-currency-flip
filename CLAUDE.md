# Instructions for AI coding agents

Before writing or modifying code in this repo, read the relevant docs first — do not rely on general knowledge or default conventions instead:

- Backend (Java): [docs/CODE_STYLE.md](docs/CODE_STYLE.md) is required reading before any backend code change. It defines naming, function design, SOLID, and the Clean Architecture layering (Entities → Use Case Interactors → Gateways → Controllers/Presenters) this codebase follows, plus error-handling and testing discipline.
- Frontend (React/TypeScript): [docs/FRONTEND_CODE_STYLE.md](docs/FRONTEND_CODE_STYLE.md) is required reading before any frontend code change. It defines the Humble Object split (components stay thin; logic lives in hooks/gateways/presenters).
- Data ingestion or anything touching external APIs (GGG, PoE Wiki): also read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) first.
- Database schema changes: also read [docs/SCHEMA.md](docs/SCHEMA.md) — new Flyway migration files only, never edits to `V1__init_schema.sql`, never Hibernate auto-ddl.

Full doc index: [README.md](README.md).

**Enforcement:** the moment a `pom.xml` exists in this repo, add the ArchUnit test described in [docs/CODE_STYLE.md § Clean Architecture](docs/CODE_STYLE.md#clean-architecture--layering-the-onion-with-names) (Day-one enforcement requirement) before writing any other backend code. Don't let the architecture rules be prose-only.

## Tooling

`gh` (GitHub CLI) is not on PATH in the default Windows shell (PowerShell/Git Bash) but is authenticated and available through WSL. When a `gh` command is needed (checking/changing the GitHub default branch, PRs, issues, etc.), run it via WSL (e.g. `wsl gh ...`) rather than reporting it as unavailable.

## Branching

`main` is this repository's mainline/default branch. A `master` branch also exists in history (currently pointing at the same commit as `main`) — treat it as legacy; never create, target, or base new work off a branch literally named `master`. Feature branches are cut from `main`, and PRs target `main`.

## Regression discipline

Whenever a bug or gap is found and fixed — in this session or a future one — add a test (or, if genuinely untestable, a documented manual-verification step) that would have caught it, committed in the same change as the fix. This applies to backend and frontend equally. A fix without a regression test is a fix that can silently come back.

Prefer fixture-based tests over mocks where the two compete: a saved real response from the actual external source (GGG, PoE Wiki, or this project's own API contract) in, an asserted normalized/parsed output out — see [docs/ARCHITECTURE.md § Contract Tests via Fixtures](docs/ARCHITECTURE.md#3-contract-tests-via-fixtures) and [docs/FRONTEND_CODE_STYLE.md § Testing](docs/FRONTEND_CODE_STYLE.md#testing). Mocking is still the right tool one layer up — for isolating a use case's own orchestration logic (e.g. a hook's state transitions) from the data it's fed — but the boundary adapter that actually talks to an external shape should be proven against real captured data, not a hand-shaped stand-in.

When verifying a fix, match the actual CI/production environment rather than just what's installed locally — Node/Java major version, OS (CI runs on Linux; local dev here is often Windows), and container vs. host all cause real behavioral differences. (Concretely: this repo's CI once passed locally on Node 24 while failing in CI's pinned Node 20, because a test dependency silently required a newer Node than CI was configured for.) Docker is available specifically to reproduce CI's environment before pushing when in doubt.

## Frontend layout discipline

Whenever a UI layout is added or changed, check it against **both** [docs/mockups/*.html](docs/mockups/) (open it in a browser — the rendered mockup, not just its HTML source, is the actual visual reference) and the relevant [PRD.md](docs/PRD.md) requirement section, before considering the work done. PRD.md's prose describes intent and requirements, not exact layout — when the two seem to disagree, the mockup wins on placement/structure/styling, and PRD.md wins on functional requirements (what must be shown, when, in what precision). Don't implement a UI feature from PRD prose alone without opening the mockup.

(Concretely: the Data Freshness Banner was first built as a full-width strip below the header, because that matched a literal reading of PRD.md § 7.6's wording ("a persistent banner... alongside the refresh control") without checking back against docs/mockups/flip-row-reference.html, which places the timestamp centered in the header itself with no separate strip and no label prefix. Had to be redone as a follow-up once the user pointed out the mismatch.)

When a mockup doesn't yet cover a new element (e.g. a second, distinctly-labeled refresh action didn't exist in the mockup before the ingestion-refresh feature), update the mockup itself in the same change, not just the real component. A mockup that's drifted out of sync with the actual UI stops being a reliable reference for the next change.
