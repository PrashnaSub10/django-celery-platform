#!/usr/bin/env bash

# ============================================================
# runtime/podman/up.sh — Podman adapter for core/up.sh
# ============================================================
# Thin shim that runs the standard up.sh launcher using Podman
# instead of Docker. All compose files and logic are shared.
#
# Usage:
#   ./runtime/podman/up.sh [up|down|restart|ps|logs]
#   MODE=full BROKER_MODE=hybrid ./runtime/podman/up.sh
#
# Prerequisites:
#   - Podman 4.x+ (with built-in `podman compose`) or podman-compose
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.."; pwd)"

# ── Detect Podman compose support ──────────────────────────
if podman compose version &>/dev/null; then
    # Podman 4.x+ with built-in compose support
    export DOCKER_HOST="${DOCKER_HOST:-}"
    export CONTAINER_RUNTIME="podman"

    # Override docker → podman via a function wrapper that
    # core/up.sh will invoke through eval.
    docker() { podman "$@"; }
    export -f docker

elif command -v podman-compose &>/dev/null; then
    # Fallback to podman-compose (pip install podman-compose)
    echo "⚠️  Using podman-compose (community tool)."
    echo "   For best results, upgrade to Podman 4.x+ with built-in compose."
    echo ""
    export CONTAINER_RUNTIME="podman-compose"

    docker() {
        if [ "$1" = "compose" ]; then
            shift
            podman-compose "$@"
        else
            podman "$@"
        fi
    }
    export -f docker

else
    echo "❌ ERROR: Neither 'podman compose' nor 'podman-compose' found."
    echo "   Install Podman 4.x+ or run: pip install podman-compose"
    exit 1
fi

echo "🐧 Using Podman as container runtime"
echo ""

# ── Delegate to core/up.sh ─────────────────────────────────
exec "$REPO_ROOT/core/up.sh" "$@"
