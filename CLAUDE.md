# Instructions for AI coding agents

Before writing or modifying code in this repo, read the relevant docs first — do not rely on general knowledge or default conventions instead:

- Backend (Java): [docs/CODE_STYLE.md](docs/CODE_STYLE.md) is required reading before any backend code change. It defines naming, function design, SOLID, and the Clean Architecture layering (Entities → Use Case Interactors → Gateways → Controllers/Presenters) this codebase follows, plus error-handling and testing discipline.
- Frontend (React/TypeScript): [docs/FRONTEND_CODE_STYLE.md](docs/FRONTEND_CODE_STYLE.md) is required reading before any frontend code change. It defines the Humble Object split (components stay thin; logic lives in hooks/gateways/presenters).
- Data ingestion or anything touching external APIs (GGG, PoE Wiki): also read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) first.
- Database schema changes: also read [docs/SCHEMA.md](docs/SCHEMA.md) — new Flyway migration files only, never edits to `V1__init_schema.sql`, never Hibernate auto-ddl.

Full doc index: [README.md](README.md).

**Enforcement:** the moment a `pom.xml` exists in this repo, add the ArchUnit test described in [docs/CODE_STYLE.md § Clean Architecture](docs/CODE_STYLE.md#clean-architecture--layering-the-onion-with-names) (Day-one enforcement requirement) before writing any other backend code. Don't let the architecture rules be prose-only.
