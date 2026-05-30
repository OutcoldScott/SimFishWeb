#!/usr/bin/env bash
# Translate vivarium-serve env vars into CLI flags, then exec the binary.
#
# Recognised env vars (defaults are baked into the Containerfile's ENV):
#   HOST            bind address           (default 0.0.0.0)
#   PORT            TCP port               (default 8080)
#   WEB_ROOT        Godot web build path   (default /opt/vivarium/web)
#   LOG_METRICS     log metrics snapshots to stdout (true sets --log-metrics);
#                   discrete events are logged regardless
#   PROMETHEUS      expose /metrics        (true sets --prometheus)
#   CLIENT_TIMEOUT  seconds before a client expires from /metrics
#   OVERLAY_LEFT          path or http(s) URL for the lower-left overlay
#   OVERLAY_LEFT_WIDTH    CSS width  for the left overlay (e.g. 120px, 10%)
#   OVERLAY_LEFT_HEIGHT   CSS height for the left overlay
#   OVERLAY_RIGHT         path or http(s) URL for the lower-right overlay
#   OVERLAY_RIGHT_WIDTH   CSS width  for the right overlay
#   OVERLAY_RIGHT_HEIGHT  CSS height for the right overlay
#
# Anything passed positionally to the container is appended last, so
#   podman run ... vivarium-serve --help
# still does what you'd expect.

set -euo pipefail

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

args=( --host "${HOST:-0.0.0.0}" --port "${PORT:-8080}" )

if [[ -n "${WEB_ROOT:-}" ]]; then
    args+=( --web-root "$WEB_ROOT" )
fi

if is_truthy "${LOG_METRICS:-}"; then
    args+=( --log-metrics )
fi

if is_truthy "${PROMETHEUS:-}"; then
    args+=( --prometheus )
fi

if [[ -n "${CLIENT_TIMEOUT:-}" ]]; then
    args+=( --client-timeout "$CLIENT_TIMEOUT" )
fi

# Corner overlays. Each --overlay-* flag is added only when the matching env
# var is set, so unspecified corners stay invisible.
if [[ -n "${OVERLAY_LEFT:-}" ]]; then
    args+=( --overlay-left "$OVERLAY_LEFT" )
fi
if [[ -n "${OVERLAY_LEFT_WIDTH:-}" ]]; then
    args+=( --overlay-left-width "$OVERLAY_LEFT_WIDTH" )
fi
if [[ -n "${OVERLAY_LEFT_HEIGHT:-}" ]]; then
    args+=( --overlay-left-height "$OVERLAY_LEFT_HEIGHT" )
fi
if [[ -n "${OVERLAY_RIGHT:-}" ]]; then
    args+=( --overlay-right "$OVERLAY_RIGHT" )
fi
if [[ -n "${OVERLAY_RIGHT_WIDTH:-}" ]]; then
    args+=( --overlay-right-width "$OVERLAY_RIGHT_WIDTH" )
fi
if [[ -n "${OVERLAY_RIGHT_HEIGHT:-}" ]]; then
    args+=( --overlay-right-height "$OVERLAY_RIGHT_HEIGHT" )
fi

exec /usr/local/bin/vivarium-serve "${args[@]}" "$@"
