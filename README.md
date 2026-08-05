# PoE Currency Exchange Flip Finder

A website that finds profitable currency flips in Path of Exile 1's Currency Exchange, using vendor recipe conversions and divination card turn-ins.

## Docs

- [docs/PRD.md](docs/PRD.md) — product spec: problem, goals, features.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system design and resilience principles. Read this before touching data-ingestion code.
- [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) — verified external API contracts (GGG endpoints, PoE Wiki). Check/update this first when an external source changes.
- [docs/TECH_STACK.md](docs/TECH_STACK.md) — technology decisions.
- [docs/SCHEMA.md](docs/SCHEMA.md) — database schema: the internal domain model everything else is normalized into.
- [docs/CODE_STYLE.md](docs/CODE_STYLE.md) — Java code style and design discipline for the backend. Any AI agent writing backend code should follow this.
- [docs/FRONTEND_CODE_STYLE.md](docs/FRONTEND_CODE_STYLE.md) — React/TypeScript code style and design discipline for the frontend. Any AI agent writing frontend code should follow this.
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — packaging, CI/CD pipeline, and the first-time Render/Neon/Vercel setup walkthrough.
