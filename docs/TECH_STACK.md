# Tech Stack

**Related docs:** [PRD.md](PRD.md) (what we're building) · [ARCHITECTURE.md](ARCHITECTURE.md) (how we isolate ourselves from external sources) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external API contracts)

## Decision: backend is required, not optional

The Currency Exchange API ([DATA_SOURCES.md](DATA_SOURCES.md)) sends no `Access-Control-Allow-Origin` header, so browsers block calling it directly from frontend JavaScript — verified by direct testing (2026-08-05). A pure client-side app cannot ingest this data. All Currency Exchange ingestion, adapters, validation, and flip-margin computation ([ARCHITECTURE.md](ARCHITECTURE.md)) must run server-side.

(The Leagues API does allow direct browser calls (`Access-Control-Allow-Origin: *`), but the backend owns it anyway for consistency and so the frontend has one API to talk to.)

## Stack

| Layer | Choice | Why |
|---|---|---|
| Backend | Java 21 + Spring Boot 3 | Owns ingestion/adapters/validation/computation — the highest-value-to-debug-yourself code, and the owner (a senior Java dev) can read and fix it directly without relying on AI to diagnose an unfamiliar language. |
| Frontend | React + TypeScript | Standard choice for a sortable/filterable data-table site; most mainstream target for AI-assisted code generation and debugging. |
| Database | PostgreSQL (via Spring Data JPA) | Stores the Currency Exchange ingestion checkpoint and normalized market state between runs, plus vendor recipe / divination card reference data. |
| Communication | REST API (JSON) | Frontend calls the backend; no need for GraphQL or websockets since this is refresh-on-demand, not a live feed. |

## Hosting (all free tiers)

| Component | Where | Notes |
|---|---|---|
| Backend | [Render.com](https://render.com) free web service | Git-push deploys, zero server maintenance. **Tradeoff:** spins down after ~15 min idle; next request pays a cold-start cost (JVM + Spring Boot boot time, roughly 20-60s) before responding. Given this app is refreshed manually and used occasionally rather than continuously, the backend will likely be asleep on most visits — accepted as a real but tolerable UX cost in exchange for $0 hosting and no ops work. |
| Database | [Neon.tech](https://neon.tech) free Postgres | Serverless Postgres, free tier does not expire (unlike some other providers' free databases). Also scale-to-zero, consistent with the low-traffic usage pattern. |
| Frontend | [Vercel](https://vercel.com) free tier | Static hosting for the React build. No cold-start concern — static assets are always served instantly regardless of backend state. |

Alternative considered and rejected for now: self-hosting on Oracle Cloud's "Always Free" ARM VM (genuinely free forever, no cold starts, but requires the owner to personally handle OS updates, uptime, backups, and TLS — real ongoing ops burden not worth it for this project's traffic level).

## Credential Policy

No API in current use requires authentication (see [DATA_SOURCES.md](DATA_SOURCES.md) — Currency Exchange and Leagues are both public, no-auth). This section is a standing principle for if that ever changes:

**The app must never hold or use a single shared API key/credential on behalf of all users.** If a future feature requires an authenticated GGG endpoint (e.g. account-scoped data), each user supplies and stores their own credential; the backend uses only the requesting user's credential for that user's requests. This avoids one user's usage exhausting a shared quota or getting a shared key rate-limited or revoked for everyone.
