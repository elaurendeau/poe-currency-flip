# Deployment & Packaging

**Related docs:** [TECH_STACK.md](TECH_STACK.md) (what's hosted where and why) · [SCHEMA.md](SCHEMA.md) (Flyway migrations, run automatically per this doc) · [ARCHITECTURE.md](ARCHITECTURE.md) (resilience principles) · [CODE_STYLE.md](CODE_STYLE.md) (Java code style/design)

## Repo layout

```
backend/         Java 21 + Spring Boot 3, Maven
frontend/        React + TypeScript
db/migration/    Flyway SQL migrations (referenced by backend at runtime)
docs/            This doc set
.github/workflows/ci-cd.yml   Build+test on every push; deploy only after tests pass on main
```

One repo, both apps — simplest for a solo project; nothing here needs the overhead of separate repos or a build orchestration tool.

## Local Development

**Prerequisites:** Docker Desktop (with its bundled Docker Compose) and Node.js 20+. The backend itself doesn't need a local JDK/Maven install for this workflow — it builds and runs entirely inside the container.

[docker-compose.yml](../docker-compose.yml) runs Postgres + the backend locally so you don't need a Neon account or an H2 workaround just to click around the app:

```bash
docker compose up --build
```

This builds `backend/Dockerfile`, runs the backend against a local Postgres (Flyway migrations apply automatically on startup, same as production), and exposes the backend on `http://localhost:8080/api`.

The frontend is not part of the compose file — run it natively for fast HMR:

```bash
cd frontend
npm run dev
```

It talks to `http://localhost:8080/api` via the committed `frontend/.env`, so no extra config is needed once `docker compose up` is running. Open `http://localhost:5173` to use the app.

To stop: `docker compose down` (and Ctrl-C the `npm run dev` process).

## Packaging

**Backend → Docker.** Rather than relying on Render (or any platform) to auto-detect and build a Java project correctly, the backend ships as a container image built from [backend/Dockerfile](../backend/Dockerfile). This is the single biggest resilience win in this section: a Dockerized app runs identically on Render, Fly.io, Cloud Run, or a laptop — if Render's terms or pricing ever change (a real risk we already flagged in [TECH_STACK.md](TECH_STACK.md)), moving hosts is a config change, not a rewrite. The Dockerfile is a two-stage build (Maven build stage, slim JRE run stage) so the shipped image doesn't carry the whole JDK/build toolchain.

**Frontend → static build, no Docker.** Vercel builds directly from the `frontend/` folder (detects `package.json`, runs `npm run build`, serves the output as static files via its CDN). No container needed — this is Vercel's native, zero-config path for a React app.

## CI/CD — [.github/workflows/ci-cd.yml](../.github/workflows/ci-cd.yml)

One workflow file, four jobs:

- `test-backend`, `test-frontend` — run on every push and PR to `dev` or `main`. This is the safety net before anything reaches `main`.
- `deploy-backend`, `deploy-frontend` — run **only** on a push to `main`, and only if the matching test job succeeded (`needs: test-backend` / `needs: test-frontend`). Each deploy job is a single `curl -X POST` to a Render or Vercel **deploy hook** URL, stored as a GitHub Actions secret (`RENDER_DEPLOY_HOOK_URL`, `VERCEL_DEPLOY_HOOK_URL`).

**Why not just let Render/Vercel auto-deploy on push (their own native behavior)?** Because that runs independently of CI — a commit that fails tests would still reach production, since Render/Vercel don't know or care what GitHub Actions decided. Gating deploy jobs on test jobs via `needs` closes that gap: a failing test can never result in a deploy. This means **Render's and Vercel's own git-triggered auto-deploy must be turned off** in their dashboards (covered in the walkthrough below) — the GitHub Actions deploy hook call is the *only* path to a deploy, not one of two.

**Flyway migrations run automatically on backend startup** — every time the backend container boots (i.e., every successful deploy), Spring Boot checks `db/migration/` against Flyway's history table in Postgres and applies any new migrations before the app starts serving traffic. No separate migration step in the pipeline is needed for a project this size.

The practical implication: merging `dev` → `main` is the actual deploy trigger. Treat that merge with the weight it deserves — it's not just a git housekeeping step, it's what ships to production.

## First-time setup walkthrough

This only needs to happen once per environment. All three platforms are free-tier, per [TECH_STACK.md](TECH_STACK.md).

### 1. Neon (database)
1. Sign up at neon.tech, create a new project.
2. Create a database (Neon gives you one by default).
3. Copy the connection string it shows you (a `postgres://...` URL) — you'll paste this into Render in step 2 below.

### 2. Render (backend)
1. Sign up at render.com, connect your GitHub account, grant it access to this repo.
2. Create a new **Web Service**, select this repo.
3. Set **Environment** to `Docker`. Leave **Root Directory** unset (repo root) and set **Dockerfile Path** to `backend/Dockerfile` under Advanced settings — the Docker build context must be the repo root, not `backend/`, because `pom.xml`'s openapi-generator step reads `../contracts/openapi.yaml`, which sits outside `backend/` (see [docker-compose.yml](../docker-compose.yml) for the same context/dockerfile split used locally).
4. Under **Environment Variables**, add `DATABASE_URL` set to the Neon connection string from step 1 (adjust to Spring Boot's expected JDBC format, e.g. prefixing with `jdbc:`). Also add `FRONTEND_ORIGIN` set to the Vercel deployment's URL from step 3 below (CORS is locked to this one origin — see [backend/src/main/java/.../WebConfig.java](../backend/src/main/java/com/poeflipfinder/backend/framework/config/WebConfig.java)).
5. **Turn auto-deploy off.** In the service's Settings, disable "Auto-Deploy" (so a raw git push does *not* trigger a deploy on its own — only the gated GitHub Actions job will).
6. Under Settings, find the **Deploy Hook** URL and copy it.
7. Deploy once manually to confirm it works. On first boot, Flyway will run [V1__init_schema.sql](../db/migration/V1__init_schema.sql) against the fresh Neon database automatically.

### 3. Vercel (frontend)
1. Sign up at vercel.com, connect GitHub, import this repo.
2. Set **Root Directory** to `frontend`.
3. Add an environment variable pointing the frontend at the backend's public URL (from Render's step 2) — e.g. `VITE_API_BASE_URL`.
4. **Turn off Vercel's automatic Git deployments** for this project (Settings → Git), for the same reason as Render above.
5. Under Settings → Git, create a **Deploy Hook** for the `main` branch and copy the URL.
6. Deploy once manually to confirm it works.

### 4. Wire the deploy hooks into GitHub Actions
1. In this repo's GitHub Settings → Secrets and variables → Actions, add two repository secrets: `RENDER_DEPLOY_HOOK_URL` and `VERCEL_DEPLOY_HOOK_URL`, using the URLs copied in steps 2 and 3 above.
2. That's it — [ci-cd.yml](../.github/workflows/ci-cd.yml)'s `deploy-backend`/`deploy-frontend` jobs already reference these secret names.

After this one-time setup, every merge to `main` runs the tests, and only on success, deploys both sides automatically via the hooks above — a broken build never reaches production.
