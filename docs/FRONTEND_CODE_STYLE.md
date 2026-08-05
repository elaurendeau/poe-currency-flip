# Code Style & Design (React/TypeScript Frontend)

**Related docs:** [CODE_STYLE.md](CODE_STYLE.md) (backend equivalent — read first; every universal rule there applies here too) · [TECH_STACK.md](TECH_STACK.md) (React + TypeScript decision, UI style) · [ARCHITECTURE.md](ARCHITECTURE.md) (system-level resilience design)

[CODE_STYLE.md](CODE_STYLE.md) covers naming, function size, comments, SOLID, and testing discipline (FIRST, TDD, Boy Scout Rule) drawn from Robert C. Martin's Clean Code material — all of it applies verbatim to TypeScript, not just Java. This document doesn't repeat those; it covers the one thing that's different for a UI: **where business logic is allowed to live**, since Uncle Bob has no React-specific writing but does have a named pattern for exactly this problem.

## The Humble Object Pattern

From *Clean Architecture*: whenever logic sits inside something inherently hard to unit test — a UI framework, a database driver — split it in two. The framework-owned part becomes a **Humble Object**: as thin and logic-free as possible, so there's barely anything in it worth testing. Everything that *is* worth testing is extracted into plain, framework-free code sitting next to it.

Applied to React: **components are Humble Objects.** A component's job is JSX and wiring — calling a hook, rendering what it returns, forwarding events. It is not where business logic, formatting decisions, or API calls live. If a component has enough logic in it to justify a unit test beyond "does it render," that logic belongs one layer down.

## Where logic actually lives

Mapping the same Clean Architecture rings from [CODE_STYLE.md § Clean Architecture](CODE_STYLE.md#clean-architecture--layering-the-onion-with-names) onto the frontend:

- **Entities** — plain TypeScript types mirroring the backend's domain model (`FlipOpportunity`, `Currency`, `League`, …), defined once and reused across every feature. No React imports, no fetch calls.
- **Use Cases (as hooks)** — a custom hook (`useFlipOpportunities`, `useLeagueSelection`) is the frontend's Interactor: it orchestrates fetching, filtering, and sorting, and returns plain data + callbacks. It contains the actual logic and is unit-testable on its own (via `@testing-library/react-hooks` or by extracting the core logic into a plain function the hook just calls) without rendering a single component.
- **Gateways** — a typed API client module (`flipOpportunityApi.ts`, `leagueApi.ts`) is the frontend's Gateway/adapter, exactly mirroring the backend's Anti-Corruption Layer principle from [ARCHITECTURE.md § 1](ARCHITECTURE.md#1-anti-corruption-layer): it's the *only* place that knows the backend's JSON response shape, and it converts that shape into the frontend's own Entity types before anything else touches it. If the backend DTO shape changes, exactly one file changes here — not every component that happens to display a flip row.
- **Presenters (as pure functions)** — formatting decisions (margin color thresholds, currency display strings, sort order, the "Start → Via → Sell" row assembly from [TECH_STACK.md § UI Style](TECH_STACK.md#ui-style)) live in plain, exported, unit-testable functions (`formatMargin(value): { text, colorClass }`), not inlined as ternaries inside JSX. A component calls the presenter function and renders its output — it does not decide the formatting itself.
- **Components (Humble Objects)** — everything above feeds into a component that is, ideally, close to a pure rendering of its props/hook output. Reading a component's JSX should tell you the visual structure; it should not require tracing conditional logic to know what will actually be shown.

## Concrete rule of thumb

If you're tempted to write an `if`/ternary chain, a `.filter()`/`.sort()`, or a `fetch`/`axios` call directly inside a component body or JSX — stop and ask which of the four things above it actually is (a use case, a gateway call, or a presenter decision), and move it there. A component file that's mostly JSX with a couple of hook calls at the top is the target shape; a component file with real business logic embedded in it is the smell this pattern exists to catch.

## Testing

Same FIRST principles as [CODE_STYLE.md § Testing](CODE_STYLE.md#testing) apply, split along the same seam as the pattern above:

- Hooks (use cases) and presenter functions get real unit tests — fast, no rendering, no DOM.
- Components (Humble Objects) get thin rendering/interaction tests (does it call the right handler on click, does it render what the hook/presenter returned) — not tests re-verifying business logic that's already covered where it actually lives.
- API client (Gateway) modules get the same fixture-based contract-test treatment as the backend adapters in [ARCHITECTURE.md § 3](ARCHITECTURE.md#3-contract-tests-via-fixtures): a saved real response in, an asserted normalized Entity out.
