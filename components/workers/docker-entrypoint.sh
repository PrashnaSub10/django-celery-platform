#!/bin/sh
set -e

# ============================================================
# docker-entrypoint.sh — Runtime dependency injection
# ============================================================
# Allows installing extra Python packages at container start
# WITHOUT requiring a full image rebuild cycle.
#
# Usage:
#   EXTRA_PIP_PACKAGES="pysmb==1.2.13 paramiko==3.4.0"
#   Or mount: -v ./my-requirements.txt:/runtime-requirements.txt
# ============================================================

echo "[entrypoint] Starting celery-microservice container..."
echo "[entrypoint] Python: $(python3 --version)"
echo "[entrypoint] Working directory: $(pwd)"

# ── CODE_SOURCE: get project code into /app ────────────────────
# Supported modes:
#   bind   — code is bind-mounted from the Docker host at /app (default)
#   image  — code was COPYed into the image at build time; /app is ready
#   volume — code is at /app via a named Docker volume; nothing to do
#   git    — clone APP_GIT_URL into /app; git pull on subsequent starts
#   pip    — install APP_PIP_PACKAGE from PyPI; code is in site-packages
#
# For bind/volume/image: this section is a no-op.
# For git/pip: dependencies are the caller's responsibility to set variables.
CODE_SOURCE="${CODE_SOURCE:-bind}"
echo "[entrypoint] CODE_SOURCE=${CODE_SOURCE}"

case "$CODE_SOURCE" in
  bind)
    # Code is at /app via a host bind-mount — nothing to do.
    ;;
  image)
    # Code was baked into the image via COPY/ADD — nothing to do.
    ;;
  volume)
    # Code is at /app via a named Docker volume — nothing to do.
    ;;
  git)
    if [ -z "${APP_GIT_URL:-}" ]; then
      echo "[entrypoint] ERROR: CODE_SOURCE=git requires APP_GIT_URL to be set."
      exit 1
    fi
    if [ -d "/app/.git" ]; then
      echo "[entrypoint] CODE_SOURCE=git: repo already present, pulling latest..."
      git -C /app pull --ff-only
    else
      echo "[entrypoint] CODE_SOURCE=git: cloning ${APP_GIT_URL} ..."
      git clone "${APP_GIT_URL}" /app
    fi
    if [ -n "${APP_GIT_BRANCH:-}" ]; then
      git -C /app checkout "${APP_GIT_BRANCH}"
    fi
    echo "[entrypoint] CODE_SOURCE=git: code ready."
    ;;
  pip)
    if [ -z "${APP_PIP_PACKAGE:-}" ]; then
      echo "[entrypoint] ERROR: CODE_SOURCE=pip requires APP_PIP_PACKAGE to be set."
      exit 1
    fi
    echo "[entrypoint] CODE_SOURCE=pip: installing ${APP_PIP_PACKAGE} ..."
    pip install --no-cache-dir "${APP_PIP_PACKAGE}"
    echo "[entrypoint] CODE_SOURCE=pip: package installed."
    ;;
  *)
    echo "[entrypoint] ERROR: Unknown CODE_SOURCE '${CODE_SOURCE}'."
    echo "[entrypoint] Valid values: bind image volume git pip"
    exit 1
    ;;
esac

# ── Runtime pip injection via env var ─────────────────────────
# WARNING: Only use EXTRA_PIP_PACKAGES in development/testing.
# In production, build a custom image with pinned dependencies instead.
if [ -n "${EXTRA_PIP_PACKAGES:-}" ]; then
    if [ "${CONTAINER_ENV:-}" = "true" ] && [ "${ALLOW_RUNTIME_PIP:-false}" != "true" ]; then
        echo "[entrypoint] WARNING: EXTRA_PIP_PACKAGES is set but ALLOW_RUNTIME_PIP is not 'true'."
        echo "[entrypoint] Skipping runtime pip install. Set ALLOW_RUNTIME_PIP=true to override (not recommended in production)."
    else
        echo "[entrypoint] Installing extra packages: ${EXTRA_PIP_PACKAGES}"
        # --require-hashes is only valid with a requirements file, not a
        # space-separated package list.  Use plain install for env-var injection.
        # shellcheck disable=SC2086
        pip install --no-cache-dir ${EXTRA_PIP_PACKAGES}
        echo "[entrypoint] Extra packages installed."
    fi
fi

# ── Runtime pip injection via mounted requirements file ───────
if [ -f "/runtime-requirements.txt" ]; then
    echo "[entrypoint] Installing from /runtime-requirements.txt"
    pip install --no-cache-dir -r /runtime-requirements.txt
    echo "[entrypoint] Runtime requirements installed successfully."
fi

# ── Project-local requirements (mounted with app volume) ─────
if [ -f "/app/requirements_celery.txt" ]; then
    echo "[entrypoint] Installing from /app/requirements_celery.txt"
    pip install --no-cache-dir -r /app/requirements_celery.txt
    echo "[entrypoint] Project celery requirements installed."
fi

# ── Wait for brokers if configured ───────────────────────────
# Exits with code 1 if the broker is not reachable within 60 seconds
# so the container fails fast rather than starting with a broken broker.
if [ "${WAIT_FOR_REDIS:-}" = "true" ]; then
    echo "[entrypoint] Waiting for Redis at ${REDIS_HOST:-redis}:${REDIS_PORT:-6379}..."
    _ready=0
    for i in $(seq 1 30); do
        if timeout 2 sh -c "echo > /dev/tcp/${REDIS_HOST:-redis}/${REDIS_PORT:-6379}" 2>/dev/null; then
            echo "[entrypoint] Redis is ready."
            _ready=1
            break
        fi
        echo "[entrypoint] Redis not ready, retry $i/30..."
        sleep 2
    done
    if [ "$_ready" -eq 0 ]; then
        echo "[entrypoint] ERROR: Redis did not become ready within 60s. Aborting."
        exit 1
    fi
fi

if [ "${WAIT_FOR_RABBITMQ:-}" = "true" ]; then
    echo "[entrypoint] Waiting for RabbitMQ at ${RABBITMQ_HOST:-rabbitmq}:${RABBITMQ_PORT:-5672}..."
    _ready=0
    for i in $(seq 1 30); do
        if timeout 2 sh -c "echo > /dev/tcp/${RABBITMQ_HOST:-rabbitmq}/${RABBITMQ_PORT:-5672}" 2>/dev/null; then
            echo "[entrypoint] RabbitMQ is ready."
            _ready=1
            break
        fi
        echo "[entrypoint] RabbitMQ not ready, retry $i/30..."
        sleep 2
    done
    if [ "$_ready" -eq 0 ]; then
        echo "[entrypoint] ERROR: RabbitMQ did not become ready within 60s. Aborting."
        exit 1
    fi
fi

if [ "${WAIT_FOR_KAFKA:-}" = "true" ]; then
    echo "[entrypoint] Waiting for Kafka at ${KAFKA_HOST:-kafka}:${KAFKA_PORT:-9092}..."
    _ready=0
    for i in $(seq 1 30); do
        if timeout 2 sh -c "echo > /dev/tcp/${KAFKA_HOST:-kafka}/${KAFKA_PORT:-9092}" 2>/dev/null; then
            echo "[entrypoint] Kafka is ready."
            _ready=1
            break
        fi
        echo "[entrypoint] Kafka not ready, retry $i/30..."
        sleep 2
    done
    if [ "$_ready" -eq 0 ]; then
        echo "[entrypoint] ERROR: Kafka did not become ready within 60s. Aborting."
        exit 1
    fi
fi

# ── Validate command before exec ─────────────────────────────
if [ "$#" -eq 0 ]; then
    echo "[entrypoint] ERROR: No command provided. Pass a Celery command as the container CMD."
    exit 1
fi

echo "[entrypoint] Launching: $*"
exec "$@"
