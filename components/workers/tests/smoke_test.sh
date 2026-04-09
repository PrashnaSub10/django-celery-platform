#!/usr/bin/env bash
# ==========================================================
# Workers Smoke Test
# ==========================================================
# Validates the Docker configurations and entrypoint script.
# ==========================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "[1/3] Validating Docker Compose syntax..."
# Export dummy values to satisfy mandatory :? variable checks during config validation
# CODE_SOURCE=bind is the default; APP_PATH is only required in that mode
export CODE_SOURCE="bind"
export APP_PATH="/tmp/dummy-app"
export REDIS_PASSWORD="smokepass"
export RABBITMQ_USER="smokeuser"
export RABBITMQ_PASSWORD="smokepass"
export FLOWER_USER="admin"
export FLOWER_PASSWORD="smokepass"
docker compose -f docker-compose.workers.yml config > /dev/null
echo "✅ Compose syntax OK."

echo "[2/3] Validating entrypoint script syntax..."
bash -n docker-entrypoint.sh
echo "✅ Entrypoint syntax OK."

echo "[3/3] Testing image metadata..."
# Check if the base image follows naming conventions if it exists locally
if docker image inspect celery-microservice:base > /dev/null 2>&1; then
    MAINTAINER=$(docker image inspect celery-microservice:base --format '{{ index .Config.Labels "maintainer" }}')
    if [ "$MAINTAINER" == "django-celery-platform" ]; then
        echo "✅ Base image metadata is correct."
    else
        echo "⚠️  Base image found but maintainer label mismatch."
    fi
else
    echo "ℹ️  Base image not found locally. Skipping runtime check."
fi

echo "All worker smoke tests passed (Static Checks complete)."
