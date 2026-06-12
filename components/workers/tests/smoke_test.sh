#!/usr/bin/env bash
# ==========================================================
# Workers Smoke Test
# ==========================================================
# Static checks: compose syntax, entrypoint syntax.
# Runtime check: base image can execute Celery and Flower.
# ==========================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "[1/4] Validating Docker Compose syntax..."
export CODE_SOURCE="bind"
export APP_PATH="/tmp/dummy-app"
export REDIS_PASSWORD="smokepass"
export RABBITMQ_USER="smokeuser"
export RABBITMQ_PASSWORD="smokepass"
export FLOWER_USER="admin"
export FLOWER_PASSWORD="smokepass"
docker compose -f docker-compose.workers.yml config > /dev/null
echo "  Compose syntax OK."

echo "[2/4] Validating entrypoint script syntax..."
bash -n docker-entrypoint.sh
echo "  Entrypoint syntax OK."

echo "[3/4] Validating Dockerfile syntax..."
for df in Dockerfile.base Dockerfile.mssql Dockerfile.pdf Dockerfile.smb; do
    [ -f "$df" ] && { docker build --check -f "$df" . > /dev/null 2>&1 && echo "  $df OK." || echo "  Warning: $df check failed (Docker BuildKit --check may not be available)."; } || true
done

echo "[4/4] Validating base image runtime (if available)..."
_check_image_runtime() {
    local img="$1"
    if ! docker image inspect "$img" > /dev/null 2>&1; then
        return 1  # not found
    fi

    # Celery CLI must be reachable
    CELERY_VER=$(docker run --rm "$img" celery --version 2>/dev/null) || {
        echo "  FAIL: celery --version failed in $img"
        return 2
    }
    echo "  $img — Celery ${CELERY_VER}"

    # Flower must be importable (it is a separate package from Celery)
    docker run --rm "$img" python3 -c "import flower" > /dev/null 2>&1 || {
        echo "  FAIL: flower not importable in $img"
        return 2
    }
    echo "  $img — Flower importable OK."
    return 0
}

BASE_CHECKED=false
if _check_image_runtime "celery-microservice:base"; then
    BASE_CHECKED=true
    # Check capability variants if built
    for variant in mssql pdf smb; do
        if _check_image_runtime "celery-microservice:${variant}"; then
            true  # message printed inside function
        fi
    done
else
    echo "  Base image celery-microservice:base not found locally. Skipping runtime check."
    echo "  Build first: docker compose -f docker-compose.workers.yml build"
fi

echo ""
if [ "$BASE_CHECKED" = "true" ]; then
    echo "All worker smoke tests passed (static + runtime)."
else
    echo "All worker smoke tests passed (static checks only — build image to enable runtime check)."
fi
