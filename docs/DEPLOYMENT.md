# Deployment & Packaging

**Related docs:** [TECH_STACK.md](TECH_STACK.md) (what's hosted where and why) · [SCHEMA.md](SCHEMA.md) (Ecto migrations, run automatically per this doc) · [ARCHITECTURE.md](ARCHITECTURE.md) (resilience principles) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design)

## Repo layout

```
app/             Elixir 1.18 + Phoenix 1.7 + LiveView 1.0
docs/            This doc set
.github/workflows/ci-cd.yml   Build+test on every push; deploy only after tests pass on main
```

One repo, one app — simplest for a solo project; nothing here needs the overhead of separate repos or a build orchestration tool.

## Live site

The actual production URL is deliberately **not** written in this repo (a public repo listing it makes the site an easy scrape/DDoS target). It's stored as a GitHub Actions repository variable instead — visible to collaborators under Settings → Secrets and variables → Actions → Variables, not to public repo visitors:

- `PRODUCTION_URL` — the Render service (expect a 20-60s cold-start delay after idle, see [TECH_STACK.md](TECH_STACK.md))

## Local Development

**Prerequisites:** Docker Desktop (with its bundled Docker Compose) for local Postgres, and [mise](https://mise.jdx.dev/) (or your own Erlang/Elixir install) for `mix`/`iex` — see `app/mix.exs` for the exact Elixir/OTP versions this targets.

[docker-compose.yml](../docker-compose.yml) runs Postgres locally so you don't need a Neon account just to click around the app:

```bash
docker compose up --build
```

Then, from `app/`:

```bash
mix deps.get
mix ecto.setup   # or mix ecto.create && mix ecto.migrate
mix phx.server
```

Open `http://localhost:4000` to use the app. LiveView's HMR-equivalent (`mix phx.server`'s live-reload) picks up template/asset changes automatically; a `.ex` change still needs a server restart.

To stop: Ctrl-C the `mix phx.server` process, then `docker compose down`.

## Packaging

**Docker.** Rather than relying on Render (or any platform) to auto-detect and build an Elixir project correctly, the app ships as a container image built from [app/Dockerfile](../app/Dockerfile) (generated via `mix phx.gen.release --docker`, a two-stage build: compiles the release and digests/minifies assets in a `hexpm/elixir` builder stage, then copies only the compiled release into a slim `debian` runtime stage). This is the single biggest resilience win in this section: a Dockerized app runs identically on Render, Fly.io, Cloud Run, or a laptop — if Render's terms or pricing ever change (a real risk flagged in [TECH_STACK.md](TECH_STACK.md)), moving hosts is a config change, not a rewrite. Build context is `app/` itself — Render's **Root Directory** is set to `app`, **Dockerfile Path** to `Dockerfile` (relative to that root).

**Build-info footer.** `.git` is not reachable inside this build at all (the build context is `app/`; `.git` lives one level up at the repo root, outside any context rooted at `app/`). `PoeFlipFinderWeb.BuildInfo`'s compile-time `@git_hash` — the "is this actually the new code?" build-info footer — instead reads `RENDER_GIT_COMMIT`, a default env var Render sets for every deploy that it also auto-forwards as a Docker build ARG for Docker-based services; the Dockerfile declares that ARG so it's visible to `mix compile`. Local dev (`mix phx.server`, no `RENDER_GIT_COMMIT`) falls back to reading `.git/HEAD` from the repo root directly; a plain local `docker build` with no `--build-arg RENDER_GIT_COMMIT=...` falls all the way back to `"unknown"`, since neither source is available there — see the module for the exact fallback chain, including an empty-string-vs-unset ARG gotcha it guards against.

**Migrations run via a chained release command.** `mix phx.gen.release` generates `bin/migrate` (runs `Ecto.Migrator` against every `:ecto_repos` entry) alongside `bin/server`. Render's free tier doesn't support a separate Pre-Deploy Command (that's a paid-instance-only field), so `app/rel/overlays/bin/start` chains them into one script (`./migrate && exec ./server`) that the Docker Command field invokes as a single token — Render's Docker Command field doesn't reliably parse shell operators like `&&` directly (confirmed by an actual failed deploy: `sh -c "bin/migrate && bin/server"` reached the container as one unsplit literal). If ever moved to a paid instance, the cleaner option is Render's native **Pre-Deploy Command** (`bin/migrate`) + **Start Command** (`bin/server`), avoiding the wrapper script.

**Local verification.** `docker build -t poe-flip-finder-app app` from the repo root (add `--build-arg RENDER_GIT_COMMIT=$(git rev-parse HEAD)` to also exercise the real build-hash path Render uses) builds the exact image Render will build. Running it needs the same env vars `config/runtime.exs` requires in `:prod` — `DATABASE_URL`, `SECRET_KEY_BASE` (`mix phx.gen.secret`), `PHX_HOST`, `PORT`, `PHX_SERVER=true` — pointed at the same local Postgres `docker-compose.yml` runs. This exact sequence — `docker build` → `bin/migrate` (or `bin/start`) against a fresh database → `bin/server` → a real HTTP request — should be run locally to confirm the release actually boots and migrates cleanly before trusting a generated Dockerfile blindly.

## CI/CD — [.github/workflows/ci-cd.yml](../.github/workflows/ci-cd.yml)

- `test-app` — runs on every push and PR to `dev` or `main`: `mix compile --warnings-as-errors` (the `boundary` library turns a layering violation into a build failure, not just a local warning), `mix credo --strict`, `mix test`. This is the safety net before anything reaches `main`.
- `deploy-app` — runs automatically on a push to `main`, or on demand from **any** branch via the Actions tab (`Run workflow` → pick a branch → `deploy_target: app`) — either way, only if `test-app` succeeded (`needs: test-app`). There's only one Render site — a second one per branch isn't worth the upkeep for a solo project at this stage — so a manual deploy from a non-`main` branch ships that branch's code to the same production site. Useful for a hotfix or previewing a feature without merging first, but treat it with the same weight as a merge to `main`. The deploy job is a single `curl -X POST` to a Render **deploy hook** URL, stored as a GitHub Actions secret (`RENDER_DEPLOY_HOOK_URL`).

**Why not just let Render auto-deploy on push (its own native behavior)?** Because that runs independently of CI — a commit that fails tests would still reach production, since Render doesn't know or care what GitHub Actions decided. Gating the deploy job on the test job via `needs` closes that gap: a failing test can never result in a deploy. This means **Render's own git-triggered auto-deploy must be turned off** in its dashboard (covered in the walkthrough below) — the GitHub Actions deploy hook call is the *only* path to a deploy, not one of two.

**Migrations run automatically on every deploy** via the chained `bin/start` release command described above — no separate migration step in the pipeline is needed for a project this size.

The practical implication: merging to `main` is the actual deploy trigger. Treat that merge with the weight it deserves — it's not just a git housekeeping step, it's what ships to production.

## First-time setup walkthrough

This only needs to happen once per environment. Both platforms are free-tier, per [TECH_STACK.md](TECH_STACK.md).

### 1. Neon (database)
1. Sign up at neon.tech, create a new project.
2. Create a database (Neon gives you one by default).
3. Copy the connection string it shows you (a `postgres://...` URL) — you'll adapt this into an `ecto://` URL for Render in step 2 below (same user/password/host, `ecto://` scheme, `?sslmode=require`).

### 2. Render (app)
1. Sign up at render.com, connect your GitHub account, grant it access to this repo.
2. Create a new **Web Service**, select this repo.
3. Set **Environment** to `Docker`. Set **Root Directory** to `app` and **Dockerfile Path** to `Dockerfile` (relative to that root).
4. Under **Environment Variables**, add: `DATABASE_URL` (the `ecto://` URL from step 1), `SECRET_KEY_BASE` (generate via `mix phx.gen.secret`), `PHX_HOST` (the Render-assigned `.onrender.com` hostname), `PHX_SERVER` = `true`, `PORT` = `10000` (Render's default for Docker services).
5. Under **Build**, set **Docker Command** to `/app/bin/start` (the chained migrate+server script — see Packaging above for why a plain `&&` in this field doesn't work).
6. **Turn auto-deploy off.** In the service's Settings, disable "Auto-Deploy" (so a raw git push does *not* trigger a deploy on its own — only the gated GitHub Actions job will).
7. Under Settings, find the **Deploy Hook** URL and copy it.
8. Deploy once manually to confirm it works. On first boot, `bin/migrate` will run the app's Ecto migrations against the fresh Neon database automatically.

### 3. Wire the deploy hook into GitHub Actions
1. In this repo's GitHub Settings → Secrets and variables → Actions, add a repository secret: `RENDER_DEPLOY_HOOK_URL`, using the URL copied in step 2 above.
2. That's it — [ci-cd.yml](../.github/workflows/ci-cd.yml)'s `deploy-app` job already references this secret name.

After this one-time setup, every merge to `main` runs the tests, and only on success, deploys via the hook above — a broken build never reaches production.
