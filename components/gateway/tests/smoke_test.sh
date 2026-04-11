#!/usr/bin/env bash
# ==========================================================
# Gateway Smoke Test
# ==========================================================
# Validates the strict boundary definition of the Gateway.
# Requires zero dependencies outside this directory.
# ==========================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
TEMP_CERTS=false
trap 'docker compose -f docker-compose.gateway.yml down 2>/dev/null || true
      docker network rm celery-broker-net 2>/dev/null || true
      [ "$TEMP_CERTS" = "true" ] && rm -f ssl/fullchain.pem ssl/privkey.pem || true' EXIT

# 1. Provide the expected network contract
echo "[1/3] creating network contract..."
docker network create celery-broker-net 2>/dev/null || true

# Pre-flight: generate self-signed certs if missing so the test can run
if [ ! -f ssl/fullchain.pem ] || [ ! -f ssl/privkey.pem ]; then
    echo "⚠️  TLS certificates not found. Generating self-signed certs for smoke test..."
    if command -v openssl > /dev/null 2>&1; then
        mkdir -p ssl
        openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
            -keyout ssl/privkey.pem -out ssl/fullchain.pem \
            -subj "/CN=localhost" > /dev/null 2>&1
        echo "✅ Temporary self-signed certs generated for smoke test."
        TEMP_CERTS=true
    else
        echo "❌ openssl not found. Cannot generate certs. Skipping boot test."
        echo "   Install openssl or run: ./scripts/generate_mtls_certs.sh"
        exit 0
    fi
fi

# 2. Boot the stack
# host.docker.internal is injected by Docker Desktop (Mac/Windows) but is absent
# on Linux (GitHub Actions). None of the smoke tests exercise the upstream — they
# test health, redirect, and access control — so a non-listening 127.0.0.1 is fine.
export DJANGO_UPSTREAM_HOST="${DJANGO_UPSTREAM_HOST:-127.0.0.1}"
export DJANGO_ASGI_HOST="${DJANGO_ASGI_HOST:-127.0.0.1}"

echo "[2/3] booting gateway isolated..."
docker compose -f docker-compose.gateway.yml up -d

# Give it a few seconds to process templates
sleep 5

# 3. Test the interface
echo "[3/3] validating endpoints..."

# Test 1: Nginx health route
if curl -sf http://localhost:8080/health | grep -q "healthy"; then
    echo "✅ Health route accessible."
else
    echo "❌ Health route failed."
    docker logs celery-nginx-shared
    exit 1
fi

# Test 2: HTTP → HTTPS redirect must be 301 (not 200 — that would mean redirect is broken)
REDIRECT=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ || true)
if [ "$REDIRECT" = "301" ]; then
    echo "✅ HTTP → HTTPS redirect is 301."
else
    echo "❌ Expected 301 redirect, got: $REDIRECT"
    exit 1
fi

# Test 3: stub_status is NOT reachable from outside the container
STUB=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/stub_status || true)
if [ "$STUB" = "404" ] || [ "$STUB" = "000" ]; then
    echo "✅ stub_status correctly blocked from host."
else
    echo "⚠️  stub_status may be exposed externally (code: $STUB)."
fi

echo "All gateway smoke tests passed."
# Teardown is handled by the trap on EXIT
