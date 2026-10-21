# syntax=docker/dockerfile:1.7
#
# Cartethyia for Railway — production image.
#
# Built from the upstream source (github.com/risunCodex/Cartethyia). There is no
# official prebuilt image on a public registry, so Railway builds this file from
# the template repository. The build is the upstream three-step pipeline
# (dashboard -> AOT bundle -> standalone binary) on the same musl toolchain, and
# the runtime stage carries exactly what the binary needs at boot: the compiled
# executable, the built dashboard, and the migrations folder.
#
# Upstream's Dockerfile runs the binary as `./cartethyia`, a relative path. This
# one uses the absolute path, which is independent of how a platform resolves
# PATH or sets the working directory.

# Must match upstream .bun-version (1.4.2) — `bun install --frozen-lockfile`
# relies on the same lockfile semantics that produced bun.lock.
ARG BUN_VERSION=1.4.2

# ─── Builder ────────────────────────────────────────────────────────────────
FROM oven/bun:${BUN_VERSION}-alpine AS builder

WORKDIR /build

# Dependency layer: source changes do not invalidate the install. The lockfile is
# frozen at the tagged release so a rolling `main` cannot make the build
# non-reproducible. `--linker isolated` is the install mode the project
# documents for Docker.
COPY package.json bun.lock tsconfig.json ./
COPY dashboard/package.json ./dashboard/package.json
RUN bun install --frozen-lockfile --linker isolated

# The dashboard imports backend types, so the source contracts must be present
# before the dashboard typecheck/build can run.
COPY src ./src
COPY dashboard ./dashboard
RUN bun run dashboard:build

# Standalone-deploy boot fallback (see the runtime stage). Kept in the builder
# so the runtime COPY can tolerate this file not existing.
COPY .env.railway* ./

# Backend bundle (Elysia AOT rewrite) then the standalone executable. These two
# MUST stay in one layer: `build:binary` compiles `dist/main.js`, the output of
# `build:aot`, and resolves it relative to the build.
COPY scripts ./scripts
COPY migrations ./migrations
RUN test -f migrations/full-postgres/0000_baseline.sql \
    && test -f migrations/lite-sqlite3/0000_baseline.sql \
    && test -f migrations/full-postgres/0001_allow_multiple_shared_keys_per_ip.sql \
    && test -f migrations/lite-sqlite3/0001_allow_multiple_shared_keys_per_ip.sql
RUN bun run build:aot && bun run build:binary --outfile /build/dist/cartethyia

# ─── Runtime ────────────────────────────────────────────────────────────────
FROM alpine:3.22

# curl powers the image HEALTHCHECK (Railway uses /health/ready on its edge).
# libgcc/libstdc++ are the Bun runtime's shared libraries.
# su-exec replaces the util-linux `setpriv` used upstream: same privilege drop,
# ~10 kB instead of a multi-package install.
RUN apk add --no-cache ca-certificates curl libgcc libstdc++ su-exec tzdata \
    && addgroup -S -g 10001 cartethyia \
    && adduser -S -D -H -u 10001 -G cartethyia cartethyia \
    && mkdir -p /app/data \
    && chown -R cartethyia:cartethyia /app

WORKDIR /app

# Migrations resolve as <cwd>/migrations, so they must sit beside the binary and
# the process must start in /app.
COPY --from=builder --chown=cartethyia:cartethyia /build/migrations ./migrations
COPY --from=builder --chown=cartethyia:cartethyia /build/dist/dashboard ./dist/dashboard
COPY --from=builder --chown=cartethyia:cartethyia /build/dist/cartethyia ./cartethyia

# Boot fallback for a standalone deploy: railway.json cannot carry variables, so
# without this the container would start with no CARTETHYIA_ENCRYPTION_KEY.
# The entrypoint loads it UNDER the real environment (service variables win).
# `.env.railway` may legally be absent from the build context (template-composer
# deploys get their variables injected by Railway, so the author may omit it);
# the wildcard COPY in the builder stage turns that case into a warning rather
# than a hard failure, and this stage then skips the copy.
COPY --from=builder --chown=cartethyia:cartethyia /build/.env.railway /app/.env.runtime

COPY --chmod=755 docker-entrypoint.sh ./entrypoint.sh

# PORT is a literal, as in the upstream image: the listener and this file's
# EXPOSE must agree, so a platform-injected PORT cannot silently move the socket
# away from the port Railway is told to route to. See DEPLOY.md before changing it.
ENV PORT=12800 \
    NODE_ENV=production \
    DASHBOARD_DIST=/app/dist/dashboard \
    CARTETHYIA_PACKAGE_ROOT=/app \
    CARTETHYIA_DATA_DIR=/app/data \
    CARTETHYIA_TELEMETRY_PAYLOAD_DIR=/app/data/telemetry-payloads \
    CARTETHYIA_INSTALL_ID_DIR=/app/data/.cartethyia \
    CARTETHYIA_CONFIG_DIR=/app/data/config

EXPOSE 12800
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-12800}/health/ready" || exit 1

# The entrypoint loads the boot-fallback env, then repairs volume ownership
# (a freshly provisioned Railway volume arrives owned by root), then drops to
# uid 10001. The working directory stays /app, where `migrations/` resolves.
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/cartethyia"]
