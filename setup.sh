#!/usr/bin/env bash
# ============================================================
# setup.sh — One-shot first-run orchestrator
# ============================================================
# Runs the implicit dependency chain explicitly and idempotently:
#   prerequisites → secrets → TLS certs → project profile
# After this, the only remaining steps are: edit celery-profile.env
# and run ./core/up.sh.
# ============================================================

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "=== django-celery-platform first-run setup ==="
echo ""

# 0. Prerequisites
_missing=0
for tool in docker openssl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "❌ Missing prerequisite: $tool"
    _missing=1
  fi
done
if ! docker compose version >/dev/null 2>&1; then
  echo "❌ Missing prerequisite: docker compose (v2 plugin)"
  _missing=1
fi
if [ "$_missing" -eq 1 ]; then
  echo ""
  echo "Install the missing tools above, then re-run ./setup.sh"
  exit 1
fi
echo "✓ Prerequisites: docker, docker compose v2, openssl"

# 1. Secrets
if [ ! -f .env.secrets ]; then
  echo "→ Generating secrets (.env.secrets)..."
  ./init-secrets.sh
else
  echo "✓ .env.secrets already exists, skipping"
fi

# 2. TLS certs (Nginx will not start without them)
CERT_DIR="components/gateway/ssl"
if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
  echo "→ Generating self-signed TLS certificates for localhost..."
  ./components/gateway/scripts/generate_mtls_certs.sh localhost
  echo "  (Production: replace with Let's Encrypt fullchain.pem + privkey.pem in $CERT_DIR/)"
else
  echo "✓ TLS certificates already exist, skipping"
fi

# 3. Project profile
if [ ! -f celery-profile.env ]; then
  echo "→ Creating celery-profile.env from template..."
  cp .celery-profile.env.example celery-profile.env
  echo ""
  echo "⚠️  NEXT: edit celery-profile.env — at minimum set:"
  echo "     PROJECT_NAME, APP_PATH, CELERY_APP_*, DJANGO_SETTINGS_MODULE"
  echo ""
  echo "   Then launch (minimal first run, Redis only):"
  echo "     MODE=minimal BROKER_MODE=redis SERVER_PROFILE=small \\"
  echo "       PROJECT_PROFILE=celery-profile.env ./core/up.sh up"
else
  echo "✓ celery-profile.env exists"
  echo ""
  echo "Ready. Launch with:"
  echo "  MODE=standard BROKER_MODE=hybrid WORKER_MODE=dual SERVER_PROFILE=small \\"
  echo "    PROJECT_PROFILE=celery-profile.env ./core/up.sh up"
fi
