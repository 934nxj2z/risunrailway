# Deploy and Host Cartethyia on Railway

Cartethyia is a self-hosted multi-provider AI gateway. It gives Claude Code,
Codex, Cursor, Cline, OpenCode, Droid and any OpenAI- or Anthropic-compatible
client one stable endpoint, while it handles provider translation, account
selection, health-aware failover, quota cooldowns, usage accounting and optional
proxy pools behind that endpoint.

This template runs Cartethyia on Railway with a persistent volume, a generated
encryption key and the public origin wired to your Railway domain. No PostgreSQL
or Redis to configure: the default **Lite** mode stores everything in embedded
SQLite on the volume.

## About Hosting Cartethyia

Hosting Cartethyia means running one long-lived Bun process that speaks both the
OpenAI and Anthropic wire protocols, plus the console dashboard served from the
same origin at `/console`. The template handles the parts that are easy to get
wrong on a PaaS:

- **Persistent state.** SQLite, the install id, the config directory and
  telemetry payload captures all live under `/app/data`, which is the mounted
  volume — a redeploy keeps your providers, accounts and API keys.
- **The encryption key.** Provider credentials and gateway API keys are stored
  encrypted with `CARTETHYIA_ENCRYPTION_KEY`. The template generates a 256-bit
  key at deploy time. Rotating it later makes every stored credential
  unreadable, so treat the deployed value as critical, or seal it.
- **The public origin.** OAuth callbacks and console links are built from
  `CARTETHYIA_PUBLIC_ORIGIN`, which derives from your Railway public domain.
- **The platform edge.** `TRUSTED_PROXY_CIDRS=platform` tells the gateway to
  read the client address from the edge's forwarded headers, so per-IP rate
  limits and model-abuse bans key on the real caller instead of Railway's proxy.
- **Zero-downtime redeploys.** Railway health-checks `/health/ready` (database
  and migrations), and the container drains in-flight streams before exit.

The first boot runs the SQLite migrations automatically and serves the console.
Open `https://<your-domain>/console`, finish the first-run wizard, add your
provider accounts and issue a gateway API key.

## Common Use Cases

- **One endpoint for every AI client.** Point Claude Code, Codex, Cursor, Cline,
  OpenCode and Droid at the same gateway base URL, each keeping its native
  protocol while Cartethyia translates per provider.
- **Survive a provider hiccup.** Health-aware routing and automatic failover move
  a request to the next viable account when a provider rate-limits, revokes a
  token or returns errors — no client-side retry logic.
- **Pool many accounts safely.** Per-account quota, cooldown and capacity
  tracking keeps a pool of provider accounts from being burnt by one busy client.
- **See what actually happened.** Usage accounting, latency, cached tokens,
  spend per model and redacted per-hop request capture in one console.
- **Share access without sharing keys.** Issue child API keys with model
  allowlists, quotas and a public enrollment page under `/share`.

## Dependencies for Cartethyia Hosting

- **Railway** — one service, one volume, one public domain.
- **A public domain** — required: the gateway builds OAuth redirect URIs from it.
- **AI provider accounts or API keys** — added after deploy in the console, or via
  the provider OAuth flows the console offers.
- **No database to provision.** Lite mode uses embedded SQLite on the volume.
  Switch to Full (external PostgreSQL) later by exporting a JSON backup from
  **Settings → Backup** and importing it into a PostgreSQL-backed service.
- **Redis is optional.** Only needed when you run more than one replica; the
  default single replica uses the in-process coordination backend.

### Deployment Dependencies

- Cartethyia repository: <https://github.com/risunCodex/Cartethyia>
- Cartethyia npm package: <https://www.npmjs.com/package/cartethyia>
- Railpack / Docker build: the image is built from source with the upstream
  three-step pipeline (dashboard → AOT bundle → standalone Bun binary), so the
  first deploy takes a few minutes.
- License: GNU GPL v3.0 only.

### Implementation Details

Routes served by the deployed service, all on the same origin:

| Route | Purpose |
| --- | --- |
| `/v1/chat/completions`, `/v1/responses`, `/v1/messages` | OpenAI chat, OpenAI Responses, Anthropic Messages |
| `/v1/completions`, `/v1/responses/compact`, `/v1/search`, `/v1/systemone`, `/v1/models` | Legacy completions, compaction, web search, System One, model list |
| `/console` | Gateway dashboard |
| `/health`, `/health/ready` | Liveness, and database/migration readiness |
| `/metrics` | Prometheus |
| `/share/:token` | Public child-key enrollment |

A client only needs the base URL and a gateway API key:

```bash
curl https://<your-domain>/v1/chat/completions \
  -H "Authorization: Bearer <gateway-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"<model-id>","messages":[{"role":"user","content":"hello"}]}'
```

Two operational notes specific to this deployment:

- **Long streams.** The gateway's own upstream deadline is 120 s by default and
  the Railway edge has its own request limit. If you generate very long
  responses, keep streaming enabled and, if responses are cut, lower the
  provider-side deadlines rather than raising request bodies first.
- **Scaling.** The volume and SQLite support exactly one replica. To scale
  horizontally, move to Full mode with PostgreSQL and add Redis (`REDIS_URL`)
  before raising `numReplicas`.

### Why Deploy Cartethyia on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will
host your infrastructure so you don't have to deal with configuration, while
allowing you to vertically and horizontally scale it.

By deploying Cartethyia on Railway, you are one step closer to supporting a
complete full-stack application with minimal burden. Host your servers,
databases, AI agents, and more on Railway.
