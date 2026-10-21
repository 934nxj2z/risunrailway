#!/bin/sh
# Cartethyia container entrypoint for Railway.
#
# Railway provisions a volume as root at the mount path. The gateway runs as the
# unprivileged uid 10001 and must be able to write its SQLite database, install
# id, and telemetry payload captures there. So: start as root, repair ownership,
# then drop to 10001 — never run the app itself as root.
#
# Upstream's version of this script asks `setpriv` to drop privileges, which
# Alpine does not ship; this one uses `su-exec` and resolves the uid/gid from the
# account instead of hardcoding 10001 in two places.

set -e

APP_USER="${APP_USER:-cartethyia}"
# In the image this account exists (created in the Dockerfile). The fallback
# keeps the script runnable outside it — including on a host where the name
# does not resolve — without tripping `set -e`.
APP_UID="$(id -u "$APP_USER" 2> /dev/null || echo 10001)"
APP_GID="$(id -g "$APP_USER" 2> /dev/null || echo 10001)"

# Gateway-owned state (lite database, install id, config) and telemetry payload
# captures. Keep both inside /app/data so the single Railway volume persists
# everything that must survive a redeploy.
STATE_DIR="${CARTETHYIA_DATA_DIR:-/app/data}"
case "$STATE_DIR" in /*) ;; *) STATE_DIR="/app/data" ;; esac

PAYLOAD_DIR="${CARTETHYIA_TELEMETRY_PAYLOAD_DIR:-/app/data/telemetry-payloads}"
case "$PAYLOAD_DIR" in
	/*) ;;
	*) PAYLOAD_DIR="/app/$PAYLOAD_DIR" ;;
esac

CONFIG_DIR="${CARTETHYIA_CONFIG_DIR:-}"
if [ -n "$CONFIG_DIR" ]; then
	case "$CONFIG_DIR" in /*) ;; *) CONFIG_DIR="/app/$CONFIG_DIR" ;; esac
fi

# Boot fallback. railway.json cannot declare variables, so a standalone deploy
# of this repo relies on /app/.env.runtime (copied from .env.railway). A real
# service variable always wins: this only fills what the process environment
# left empty.
#
# Placeholder values are recorded as MISSING instead of being exported. Those
# are either unresolved `${{...}}` expressions (Railway did not render this
# file) or the repository's own `replace-with-...` defaults. Exporting them
# would resolve to "set but wrong" and defeat the app's fail-fast checks — on a
# public URL, a known encryption key is worse than no boot at all.
ENV_FALLBACK_FILE="/app/.env.runtime"
MISSING_VARS=""
if [ -f "$ENV_FALLBACK_FILE" ]; then
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			'' | '#'*)
				continue
				;;
		esac
		case "$line" in *=*) ;; *) continue ;; esac
		key="${line%%=*}"
		value="${line#*=}"
		case "$key" in *[!A-Za-z0-9_]*) continue ;; esac
		value_trimmed="$(printf '%s' "$value" | tr -d '[:space:]')"
		[ -n "$value_trimmed" ] || continue
		# Bare `${{` is the literal Railway template marker quoted on purpose.
		# The prefix match is deliberately narrow: a placeholder's tail is random
		# hex, but a real key is 64 hex chars, which can legitimately contain any
		# word-shaped substring (e.g. "abcdef0").
		# shellcheck disable=SC2016
		case "$value" in
			*'${{'* | replace-with-*)
				MISSING_VARS="${MISSING_VARS}${MISSING_VARS:+, }${key}"
				continue
				;;
		esac
		if [ -z "$(printenv "$key" 2> /dev/null)" ]; then
			export "$key=$value"
		fi
	done < "$ENV_FALLBACK_FILE"
fi

if [ -n "$MISSING_VARS" ]; then
	echo "cartethyia: these variables have no value and no usable fallback: ${MISSING_VARS}" >&2
	echo "cartethyia: set them as Railway service variables (and give the service a public domain for CARTETHYIA_PUBLIC_ORIGIN)," >&2
	echo "cartethyia: or deploy through the template, which supplies them. Refusing to start with a placeholder key." >&2
	exit 1
fi

if [ "$(id -u)" = "0" ]; then
	mkdir -p "$STATE_DIR" "$PAYLOAD_DIR" ${CONFIG_DIR:+"$CONFIG_DIR"} 2> /dev/null || true
	chown -R "$APP_UID:$APP_GID" "$STATE_DIR" "$PAYLOAD_DIR" ${CONFIG_DIR:+"$CONFIG_DIR"} 2> /dev/null || true
	exec su-exec "$APP_UID:$APP_GID" "$@"
fi

# Started unprivileged (platform forbids root, or the operator pinned a user):
# nothing can be repaired from here, so say exactly what the mount needs.
if [ ! -w "$STATE_DIR" ]; then
	echo "cartethyia: $STATE_DIR is not writable by uid $(id -u); the lite database cannot start here." >&2
	echo "cartethyia: chown it to $APP_UID:$APP_GID on the host, or let the entrypoint start as root so it can fix the mount." >&2
fi
if [ ! -w "$PAYLOAD_DIR" ]; then
	echo "cartethyia: $PAYLOAD_DIR is not writable by uid $(id -u); telemetry payload capture will fail." >&2
fi

exec "$@"
