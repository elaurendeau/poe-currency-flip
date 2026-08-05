# Code Style & Design (Java/Backend)

**Related docs:** [ARCHITECTURE.md](ARCHITECTURE.md) (system-level resilience design) · [TECH_STACK.md](TECH_STACK.md) (technology decisions) · [SCHEMA.md](SCHEMA.md) (database schema) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline) · [FRONTEND_CODE_STYLE.md](FRONTEND_CODE_STYLE.md) (React/TypeScript equivalent)

This document defines *how Java code in the backend is written* — naming, functions, class design, error handling, and testing discipline. It follows Robert C. Martin's ("Uncle Bob") Clean Code, SOLID, and Clean Architecture material. [ARCHITECTURE.md](ARCHITECTURE.md) defines the system-level shape (adapters, anti-corruption layer, ingestion model); this document defines the code-level discipline inside and around that shape. Any AI coding agent writing or modifying Java code in this repo should follow this document.

## Naming

- Names must reveal intent. A reader should not need to open the implementation to know what a variable, function, or class is for. `checkpointNextChangeId` beats `id`; `filterOutSoloSelfFound` beats `filter2`.
- No mental mapping. Don't make the reader translate `e` back to `exchangeSnapshot` in their head. Loop indices in a tight 2–3 line scope (`i`, `j`) are the only exception.
- No noise words. `CurrencyData`, `CurrencyInfo`, `CurrencyManager` — `Data`, `Info`, `Manager` add nothing. Say what the class actually does: `CurrencyExchangeAdapter`, `LeagueResolver`.
- One word per concept, project-wide. Don't mix `fetch`, `retrieve`, and `get` for the same kind of operation across classes. Pick one verb per concept and use it consistently (this codebase standardizes on `fetch*` for outbound HTTP calls, `resolve*` for computed/derived lookups like league resolution, `normalize*` for adapter raw→domain conversion).
- Class names are nouns (`ExchangeMarketSnapshot`, `VendorRecipeAdapter`), method names are verb phrases (`normalizeSnapshot`, `computeMargin`). A method returning a boolean reads as a predicate (`isSoloSelfFound`, `hasStaleCheckpoint`).
- Searchable names. Avoid single-letter or magic-number constants outside tiny local scopes — `MAX_CATCHUP_HOURS` beats a bare `168` inlined in ingestion logic.

## Functions

- Small, and doing one thing. If you can extract a chunk of a method under a descriptive name and it isn't just restating what the code already said, it wasn't one thing.
- One level of abstraction per function. Don't mix "walk the checkpoint forward hour by hour" with "parse this specific JSON field" in the same method — the second belongs one level down, inside the adapter's parsing step.
- Few arguments. Zero or one is ideal; two is fine; three needs a reason; four or more means the arguments almost certainly want to be a parameter object (e.g. bundle `league`, `startHour`, `endHour` into a `CatchupWindow` rather than passing them loose).
- No boolean flag arguments. `ingest(checkpoint, true)` forces the reader to go check what `true` means. Split into two named methods, or use an enum.
- No output arguments. A function returns its result; it doesn't mutate a parameter passed in to smuggle a second return value out.
- Command-query separation. A method either *does* something (command, void return) or *answers* something (query, no side effects) — never both. `resolveDefaultLeague()` should not also have the side effect of writing a cache row; if it needs to, split the read and the write into two calls.
- Exceptions over error codes, and extract the try/catch body into its own function so error handling isn't tangled with the happy path.

## Comments

- Prefer expressive code over comments. Most comments exist because the code failed to say what it meant — fix the code first.
- Don't comment what the code says; comment *why*, when the why isn't derivable from reading it (a workaround for a specific GGG API quirk, a non-obvious ordering constraint, a deliberate tradeoff). This matches the project convention already used in [ARCHITECTURE.md](ARCHITECTURE.md) — e.g., *why* the ingestion generation-tag swap exists (atomicity), not a restatement of *what* it does.
- No commented-out code. Delete it — git history has it if it's ever needed again.
- No changelog/attribution comments in code (`// added by X for feature Y`, `// fixed 2026-01-01`). That belongs in the commit message and rots in place otherwise.

## Formatting

- A class reads top-to-bottom like a newspaper article: high-level policy first, increasingly detailed private helpers below, in the order they're called (the "step-down rule").
- Related concepts stay vertically close: a method and the private helper it exclusively calls belong near each other, not scattered alphabetically.
- Keep lines short enough to read without scrolling; keep files focused enough that no single class file becomes a dumping ground (a class doing one thing rarely needs to be huge).

## Objects, Data, and the Law of Demeter

- Objects hide their data behind behavior; data structures expose their data and have no meaningful behavior. Don't build hybrids that are half-encapsulated, half-exposed — they get the worst of both (hard to add new data shapes *and* hard to add new behavior).
- Domain types described in [ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer) (`Currency`, `ExchangeMarketSnapshot`, `FlipOpportunity`, etc.) are the project's data structures — plain, adapter-produced, no business logic embedded in them. Behavior that operates on them (margin computation, filtering) lives in services, not as methods bolted onto the data type.
- Law of Demeter: a method should only call methods on (1) itself, (2) objects it created, (3) objects passed into it, (4) objects it directly holds as a field — not on some object returned by another call (`snapshot.getMarket().getRates().getPrimary()` is a chain to avoid; ask the object that actually owns the concept for what you need instead).

## SOLID

- **Single Responsibility** — a class has exactly one reason to change. `CurrencyExchangeIngestionService` orchestrating the checkpoint walk is one responsibility; parsing GGG's raw JSON is a different one and belongs in the adapter, not inlined into the service (see [ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer)).
- **Open/Closed** — adding a new flip-finding feature (Features A–E per [PRD.md](PRD.md)) should mean *adding* a new strategy/service class, not editing a growing `if/else` chain inside an existing one. New external data source → new adapter class, not a new branch in an existing adapter.
- **Liskov Substitution** — any implementation of an interface (e.g. multiple adapters implementing a common `ExternalSourceAdapter<T>` contract) must be usable anywhere the interface is expected, with no caller needing to know or check which concrete type it got.
- **Interface Segregation** — don't force a class to implement methods it doesn't need. Prefer a few narrow interfaces (`SnapshotReader`, `SnapshotWriter`) over one fat interface a caller only partially uses.
- **Dependency Inversion** — high-level policy (ingestion orchestration, flip computation) depends on abstractions, not on concrete external clients. The ingestion interactor depends on an `ExchangeSourceGateway` interface; the concrete GGG HTTP client is an implementation injected underneath it (naturally expressed via Spring beans/constructor injection). This is what makes the Gateway boundary described below real in code, not just in prose — nothing above the gateway interface may import a GGG-specific type.

## Clean Architecture / Layering (the Onion, with names)

Concentric rings, dependencies point inward only (**the Dependency Rule**): nothing in an inner ring may name, import, or know about anything in an outer ring. Outer rings depend inward; inner rings never depend outward. Where an inner ring needs something an outer ring provides (persistence, an external API), the inner ring defines an interface and the outer ring implements it — dependency *and* control flow point opposite directions at that seam.

Ring by ring, innermost first, with the concrete Java shape each takes in this codebase:

- **Entities** — the enterprise-wide business objects: `Currency`, `League`, `ExchangeMarketSnapshot`, `VendorRecipe`, `DivinationCardReward`, `FlipOpportunity` from [ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer). Plain Java, no framework imports, no persistence/HTTP annotations. These change only when the business rules themselves change, never because a library or a delivery mechanism changed.
- **Use Cases (Interactors)** — one class per application-specific operation: `ComputeFlipOpportunitiesInteractor`, `RunIngestionCatchupInteractor`, `ResolveLeagueListInteractor`. Each implements an **Input Boundary** interface (`ComputeFlipOpportunitiesInputBoundary`) so the ring outside it depends on an abstraction, not the concrete class. An interactor orchestrates entities to satisfy one use case and knows nothing about HTTP, SQL, or JSON.
- **Gateways** — interfaces the use-case ring *defines* for whatever it needs from the outside world (`ExchangeSourceGateway`, `SnapshotRepositoryGateway`, `LeagueGateway`, `VendorRecipeGateway`). This is the same seam [ARCHITECTURE.md](ARCHITECTURE.md) calls the Anti-Corruption Layer, named Uncle Bob's way: the interactor calls `ExchangeSourceGateway.fetchHour(changeId)` and has no idea whether the implementation behind it is a GGG HTTP client or a test fixture.
- **Controllers** — one per inbound entry point (`FlipOpportunityController`, `RefreshController`). A controller's only job is: take a raw request, build the interactor's **Request Model** (a plain data holder, not the HTTP DTO and not an entity), and invoke the Input Boundary. No business logic, no direct entity manipulation.
- **Presenters** — take the interactor's **Response/Output Model** and shape it into a **ViewModel** ready for the delivery mechanism (JSON DTO fields, formatted percentages, pre-sorted lists) — formatting decisions live here, not in the interactor. A presenter implements the interactor's **Output Boundary** interface, so the interactor calls `outputBoundary.present(result)` without knowing a presenter (rather than, say, a test spy) is on the other end.
- **Frameworks & Drivers (outermost)** — Spring MVC (`@RestController` classes wiring Controller+Presenter+Interactor together), Spring Data JPA repository implementations of the Gateway interfaces, the GGG HTTP client, Flyway migrations. This ring is deliberately thin and replaceable; it exists to plug frameworks into the boundaries the inner rings defined, never the reverse.

**Pragmatic note for this project's size:** full Controller/Presenter/Interactor/Boundary ceremony earns its keep for the one piece of logic worth protecting from the framework and worth unit-testing in isolation — flip-opportunity computation (Features A–E) and the ingestion catch-up walk. For simple pass-through reads (e.g. "list current leagues"), a thin `@RestController` calling a use-case interactor directly and mapping its Response Model straight to a DTO is enough; don't force a Presenter class into existence for a use case that has no real formatting logic. The Dependency Rule (entities and use cases never import Spring/JPA/HTTP types) is the non-negotiable part — the Controller/Presenter split is the part to apply where it pays for itself.

**Concrete test of whether this is being followed:** the entities and use-case packages should compile with zero `org.springframework.*`, `jakarta.persistence.*`, or HTTP-client imports. If `ComputeFlipOpportunitiesInteractor` needs a Spring import to work, the Dependency Rule has already leaked.

**Day-one enforcement requirement:** a prose rule nobody checks eventually gets violated. The first time a `pom.xml` exists in this repo, add an [ArchUnit](https://www.archunit.org/) test (or equivalent) that mechanically asserts the entities and use-case packages have zero dependencies on Spring/JPA/HTTP-client packages, and run it in CI alongside the rest of the test suite. This turns the Dependency Rule from a convention into a build failure — don't let this doc be the only thing enforcing it.

## Error Handling

- Fail loudly at the boundary — this project already commits to this in [ARCHITECTURE.md § 2](ARCHITECTURE.md#2-validate-at-the-boundary-fail-loudly). In code terms: adapters validate and throw a specific, named exception (`ExchangeSchemaValidationException`, not a bare `RuntimeException`) the moment raw data doesn't match the expected shape. Don't let a malformed field surface later as a `NullPointerException` three calls downstream.
- Use unchecked exceptions for the failure classes defined here (schema validation, unexpected upstream shape, network failure mid-walk) and let them propagate to one centralized handler (a `@ControllerAdvice` at the web layer) rather than catching-and-swallowing in the service or adapter.
- Never catch an exception you can't meaningfully handle. Catching `Exception` just to log and continue is what produces the "silently wrong" failure mode [ARCHITECTURE.md](ARCHITECTURE.md) explicitly rejects.
- Provide context in exception messages (which league, which change-stream hour, which field failed validation) — the message is what an AI agent or the maintainer sees first when a fixture-based contract test ([ARCHITECTURE.md § 3](ARCHITECTURE.md#3-contract-tests-via-fixtures)) fails.

## Testing

- Follow the **Three Laws of TDD** where practical for new business logic (margin computation, league resolution, checkpoint-walk logic): write a failing test before the production code that makes it pass, and write no more of either than the minimum needed to progress.
- Tests are **FIRST**: Fast, Independent, Repeatable (no reliance on live GGG state), Self-validating (pass/fail, no manual log inspection), Timely (written alongside the code, not after).
- One assertion concept per test; a test name states the scenario and expectation (`walkFromCheckpoint_stopsAtCurrentHour_withoutOverrunning`), not `test1`.
- Adapter tests are fixture-based per [ARCHITECTURE.md § 3](ARCHITECTURE.md#3-contract-tests-via-fixtures) — a committed real sample response in, an asserted normalized domain object out. This is the project's primary defense against silent upstream drift; treat these as required, not optional, for every adapter.
- Test code follows the same naming and single-responsibility discipline as production code — a test is not a dumping ground exempt from Clean Code because "it's just a test."

## The Boy Scout Rule

Leave code cleaner than you found it. A small drive-by improvement (a better name, an extracted method, a removed dead branch) is welcome in a change that's already touching that file — but keep it small and don't let an unrelated cleanup balloon the size of an otherwise-focused change.
