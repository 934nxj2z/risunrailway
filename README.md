# Cartethyia on Railway

A one-click Railway template for [Cartethyia](https://github.com/risunCodex/Cartethyia),
the self-hosted multi-provider AI gateway: one OpenAI- and
Anthropic-compatible endpoint in front of your provider accounts, with
health-aware failover, quota/cooldown enforcement, usage accounting and a
console at `/console`.

Modelled on the `9router` Railway template: one service, one volume, one public
domain, and a generated secret so the deploy needs no manual variables.

> **Upstream has no prebuilt image.** This template therefore builds Cartethyia
> from source with the same pipeline upstream uses (dashboard → AOT bundle →
> standalone Bun binary). The first deploy takes a few minutes; later deploys
> reuse the dependency layers.

## What deploying gives you

| | |
| --- | --- |
| Service | one container, `PORT=12800` |
| Volume | mounted at `/app/data` — SQLite, install id, config, payload captures |
| Secret | `CARTETHYIA_ENCRYPTION_KEY`, 256-bit, generated per deploy |
| Origin | `CARTETHYIA_PUBLIC_ORIGIN=https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| Edge | `TRUSTED_PROXY_CIDRS=platform` so per-IP limits see real clients |
| Health | `/health/ready` (database + migrations), 300 s grace |
| Shutdown | `drainingSeconds: 40` — in-flight streams drain before SIGKILL |
| Database | embedded SQLite (Lite). PostgreSQL is not required |

## Deploy

### As a template (recommended)

1. Publish this repository as a Railway template (Templates → New Template,
   source: this GitHub repo, branch `main`).
2. Template config, which `railway.json` cannot express:

   | Setting | Value |
   | --- | --- |
   | Volume | one, mount path `/app/data` |
   | Public networking | HTTP, generate a Railway domain |
   | `CARTETHYIA_DB_MODE` | `lite` |
   | `CARTETHYIA_ENCRYPTION_KEY` | `${{secret(64, "abcdef0123456789")}}` |
   | `CARTETHYIA_PUBLIC_ORIGIN` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
   | `TRUSTED_PROXY_CIDRS` | `platform` |
   | `NODE_ENV` | `production` |
   | `LOG_LEVEL` | `info` |

   The remaining paths (`CARTETHYIA_DATA_DIR`, `CARTETHYIA_TELEMETRY_PAYLOAD_DIR`,
   `CARTETHYIA_INSTALL_ID_DIR`, `DASHBOARD_DIST`) are already set inside the
   image and do not need to be repeated.

   **Change that secret pattern.** The literal `abcdef0123456789` above is the
   one the 9Router template uses; upstream Cartethyia's GitHub was flagged as
   automated star activity, so this repo deliberately ships a different,
   randomly generated pattern in [`.env.railway`](.env.railway) — use the same
   one, or any other random value.

3. Description for the template page: paste [`DEPLOY.md`](DEPLOY.md).

Updates: because the template is backed by this GitHub repository, merging to
`main` notifies users of an available update.

### Straight from this repo (no template)

Railway builds `Dockerfile` via `railway.json`. `railway.json` cannot declare
variables, so the image ships a boot fallback ([`.env.railway`](.env.railway))
that the entrypoint loads *under* the real environment. You still must set:

- `CARTETHYIA_ENCRYPTION_KEY` → `openssl rand -hex 32`
  (the placeholder in `.env.railway` deliberately stops the boot otherwise)
- a public domain, so `CARTETHYIA_PUBLIC_ORIGIN` resolves

and attach a volume at `/app/data`.

When Railway suggests variables from [`.env.example`](.env.example), accept only
the names that make sense and fill in real values — its
`CARTETHYIA_ENCRYPTION_KEY` is intentionally empty.

### Local Docker test

```bash
cp .env.example .env          # then set a real key: openssl rand -hex 32
docker compose up --build -d
curl -s http://127.0.0.1:12800/health/ready
```

The compose file reads `.env` (upstream's pattern), and anything in its
`environment:` block wins over that file.

## First run

1. Open `https://<your-domain>/console`.
2. Complete the first-run wizard, add provider accounts, and let the health
   sweep pick them up.
3. Issue a gateway API key. `GET /v1/models` with that key lists what the key may
   call.
4. Point a client at `https://<your-domain>` — it keeps its native protocol.

## Operate

| Concern | Where |
| --- | --- |
| Logs | Railway deploy logs; `LOG_LEVEL` controls verbosity |
| Readiness | `GET /health/ready` — `503` while migrations run or the DB is down |
| Metrics | `GET /metrics` (Prometheus) |
| Backup | console → Settings → Backup (JSON export) |
| Migrate to PostgreSQL | set `CARTETHYIA_DB_MODE=full` + `DATABASE_URL`, wait for `/health/ready`, import the backup |

**Never rotate `CARTETHYIA_ENCRYPTION_KEY` casually** — it encrypts stored
provider credentials and API keys; a new key makes existing ones unreadable.

**Scaling.** SQLite + one volume means one replica. For several replicas: Full
mode with PostgreSQL, plus `REDIS_URL` for shared coordination, before raising
`numReplicas`.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile` | production image (upstream build pipeline, non-root runtime) |
| `docker-entrypoint.sh` | boot-fallback env load, volume ownership repair, privilege drop |
| `railway.json` | build/deploy settings Railway reads |
| `.env.railway` | default variables + placeholders for a standalone deploy |
| `.env.example` | env file for the local compose run |
| `.railway/railway.ts` | optional Infrastructure-as-Code mirror (`railway config`) |
| `DEPLOY.md` | template overview page copy |
| `docker-compose.yml` | local reproduction of the deploy |

## Notes on this template

- The build targets the upstream release this template was written against
  (tag `v2.4.6`, Bun `1.4.2`). To move it forward, point the template source at
  the newer tag and bump `BUN_VERSION` if upstream's `.bun-version` changed,
  then verify `/health/ready` and the console before publishing the update.
- The runtime image does not run the app as root: the entrypoint repairs volume
  ownership, then drops to uid `10001`.
- License: this template's files are provided as-is; Cartethyia itself is
  [GPL-3.0-only](https://github.com/risunCodex/Cartethyia/blob/main/LICENSE).
