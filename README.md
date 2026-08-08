# PoE Currency Exchange Flip Finder

A website that finds profitable currency flips in Path of Exile 1's Currency Exchange, using vendor recipe conversions and divination card turn-ins.

## Docs

- [docs/PRD.md](docs/PRD.md) — product spec: problem, goals, features.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system design and resilience principles. Read this before touching data-ingestion code.
- [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) — verified external API contracts (GGG endpoints, PoE Wiki). Check/update this first when an external source changes.
- [docs/TECH_STACK.md](docs/TECH_STACK.md) — technology decisions.
- [docs/SCHEMA.md](docs/SCHEMA.md) — database schema: the internal domain model everything else is normalized into.
- [docs/CODE_STYLE.md](docs/CODE_STYLE.md) — Elixir code style and design discipline. Any AI agent writing code in this repo should follow this.
- [docs/ELIXIR_TEST_MANIFESTO.md](docs/ELIXIR_TEST_MANIFESTO.md) — testing discipline: outside-in TDD, fixture-based integration tests, the Use-Case Discovery Procedure. Any AI agent writing a test should follow this.
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — packaging, CI/CD pipeline, and the first-time Render/Neon setup walkthrough.
