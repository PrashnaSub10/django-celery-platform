#!/usr/bin/env bash

# ============================================================
# up.sh — Smart Launcher for Composable Infrastructure
# ============================================================
# This script encodes engineering judgment by layering
# composable parts of the infrastructure based on the user's
# needs, avoiding a monolithic deployment.
# ============================================================

set -euo pipefail

# Always resolve paths relative to the repo root, regardless of where
# the script is invoked from. core/up.sh lives one level below root.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
cd "$REPO_ROOT"

# Default variables
MODE=${MODE:-standard}                   # minimal | standard | full
BROKER_MODE=${BROKER_MODE:-redis}        # redis | rabbitmq | hybrid
WORKER_MODE=${WORKER_MODE:-single}       # single | dual
SERVER_PROFILE=${SERVER_PROFILE:-medium} # small | medium | large
CODE_SOURCE=${CODE_SOURCE:-bind}         # bind | image | git | volume | pip
PROJECT_PROFILE=${PROJECT_PROFILE:-.env.example}
ASGI_MODE=${ASGI_MODE:-false}            # true | false — enables Daphne + Redis Channel Layer
COMMAND=${1:-up}                         # up | down | restart | ps | logs

# Check for secrets file
if [ ! -f .env.secrets ]; then
    echo "❌ ERROR: .env.secrets file not found."
    echo "   Please run ./init-secrets.sh first."
    exit 1
fi

# Warn if deploying without a real project profile
if [ "$PROJECT_PROFILE" = ".env.example" ]; then
    echo "⚠️  WARNING: PROJECT_PROFILE not set. Using dummy .env.example."
    echo "    Usage: PROJECT_PROFILE=/path/to/my/celery-profile.env ./up.sh"
    echo ""
fi

# Pre-flight checks only needed for 'up' and 'restart'
if [ "$COMMAND" = "up" ] || [ "$COMMAND" = "restart" ]; then

  if [ "$PROJECT_PROFILE" != ".env.example" ] && [ -f "$PROJECT_PROFILE" ]; then
    # Read only simple KEY=VALUE lines; reject lines with shell metacharacters
    # to prevent code injection via a malicious PROJECT_PROFILE file.
    while IFS='=' read -r key value; do
      case "$key" in
        ''|\#*) continue ;;
      esac
      # Reject keys or values containing shell metacharacters
      case "$key$value" in
        *[\'\"\;\&\|\`\$\(\)\{\}\<\>]*) continue ;;
      esac
      export "$key=$value"
    done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$PROJECT_PROFILE" || true)
  fi

  # Validate dimension values against allowed sets before using them in file paths.
  case "$MODE" in
    minimal|standard|full) ;;
    *) echo "❌ ERROR: MODE must be one of: minimal standard full (got: $MODE)"; exit 1 ;;
  esac
  case "$BROKER_MODE" in
    redis|rabbitmq|hybrid|kafka) ;;
    *) echo "❌ ERROR: BROKER_MODE must be one of: redis rabbitmq hybrid kafka (got: $BROKER_MODE)"; exit 1 ;;
  esac
  case "$WORKER_MODE" in
    single|dual) ;;
    *) echo "❌ ERROR: WORKER_MODE must be one of: single dual (got: $WORKER_MODE)"; exit 1 ;;
  esac
  case "$SERVER_PROFILE" in
    small|medium|large) ;;
    *) echo "❌ ERROR: SERVER_PROFILE must be one of: small medium large (got: $SERVER_PROFILE)"; exit 1 ;;
  esac
  case "$CODE_SOURCE" in
    bind|image|git|volume|pip) ;;
    *) echo "❌ ERROR: CODE_SOURCE must be one of: bind image git volume pip (got: $CODE_SOURCE)"; exit 1 ;;
  esac

  # TLS preflight — Nginx will not start without certificates, and the
  # resulting compose error is cryptic. Fail here with the exact fix instead.
  CERT_DIR="components/gateway/ssl"
  if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
    echo "❌ ERROR: TLS certificates not found in $CERT_DIR/"
    echo "   The gateway (Nginx) requires fullchain.pem + privkey.pem to start."
    echo "   Local/dev:   ./components/gateway/scripts/generate_mtls_certs.sh localhost"
    echo "   Production:  copy your Let's Encrypt fullchain.pem + privkey.pem there."
    echo "   Then re-run this command."
    exit 1
  fi

  # Validate required variables per CODE_SOURCE mode
  case "$CODE_SOURCE" in
    bind)
      if [ -z "${APP_PATH:-}" ]; then
        echo "❌ ERROR: CODE_SOURCE=bind requires APP_PATH."
        echo "   Set APP_PATH=/absolute/path/to/your/django-project in: $PROJECT_PROFILE"
        exit 1
      fi
      if [ ! -d "$APP_PATH" ]; then
        echo "❌ ERROR: CODE_SOURCE=bind but APP_PATH='$APP_PATH' does not exist on this host."
        echo "   Workers would start, fail to import your code, and restart in a loop."
        echo "   Set APP_PATH to the absolute path of your Django project in: $PROJECT_PROFILE"
        exit 1
      fi
      ;;
    volume)
      if [ -z "${APP_VOLUME_NAME:-}" ]; then
        echo "❌ ERROR: CODE_SOURCE=volume requires APP_VOLUME_NAME."
        echo "   Set APP_VOLUME_NAME=<docker-volume-name> in: $PROJECT_PROFILE"
        exit 1
      fi
      ;;
    git)
      if [ -z "${APP_GIT_URL:-}" ]; then
        echo "❌ ERROR: CODE_SOURCE=git requires APP_GIT_URL."
        echo "   Set APP_GIT_URL=https://github.com/your-org/your-project.git in: $PROJECT_PROFILE"
        exit 1
      fi
      ;;
    pip)
      if [ -z "${APP_PIP_PACKAGE:-}" ]; then
        echo "❌ ERROR: CODE_SOURCE=pip requires APP_PIP_PACKAGE."
        echo "   Set APP_PIP_PACKAGE=your-django-project==1.2.3 in: $PROJECT_PROFILE"
        exit 1
      fi
      ;;
    image)
      # Code is baked into WORKER_IMAGE at build time — no extra variable required.
      ;;
  esac

  for file in "core/modes/${MODE}.yml" "components/workers/strategies/broker.${BROKER_MODE}.env" "core/profiles/sizing.${SERVER_PROFILE}.env"; do
    if [ ! -f "$file" ]; then
      echo "❌ ERROR: Configuration file $file does not exist."
      exit 1
    fi
  done

  if [ "$MODE" = "minimal" ] && [ "$BROKER_MODE" != "redis" ]; then
    echo "⚠️  WARNING: MODE=minimal disables RabbitMQ (scale: 0)."
    echo "   BROKER_MODE=${BROKER_MODE} will have no effect — worker-critical will not run."
    echo "   Use MODE=standard or MODE=full for RabbitMQ or hybrid broker strategies."
    echo ""
  fi

  # WORKER_MODE=dual requires BROKER_MODE=hybrid — both brokers must be running
  if [ "$WORKER_MODE" = "dual" ] && [ "$BROKER_MODE" != "hybrid" ]; then
    echo "❌ ERROR: WORKER_MODE=dual requires BROKER_MODE=hybrid."
    echo "   dual mode runs both worker-fast (Redis) and worker-critical (RabbitMQ)"
    echo "   with a unified Flower UI. Both brokers must be active."
    echo "   Set BROKER_MODE=hybrid or use WORKER_MODE=single."
    exit 1
  fi

  # BROKER_MODE=kafka requires WORKER_MODE=single — Kafka workers are a separate lane
  if [ "$BROKER_MODE" = "kafka" ] && [ "$WORKER_MODE" = "dual" ]; then
    echo "❌ ERROR: BROKER_MODE=kafka is not compatible with WORKER_MODE=dual."
    echo "   dual mode requires BROKER_MODE=hybrid (Redis + RabbitMQ)."
    echo "   Kafka runs as a standalone broker lane. Use WORKER_MODE=single."
    exit 1
  fi

  # Sanity-check Celery app entrypoints — a wrong format produces a worker
  # import crash-loop with the error buried in docker logs.
  for _app_var in CELERY_APP_REDIS CELERY_APP_RABBITMQ CELERY_APP_KAFKA; do
    eval "_app_val=\${$_app_var:-}"
    if [ -n "$_app_val" ]; then
      case "$_app_val" in
        *:*) ;;
        *)
          echo "⚠️  WARNING: ${_app_var}='${_app_val}' is not module:attribute format."
          echo "   Expected example: config.celery_hybrid:app_redis"
          echo ""
          ;;
      esac
    fi
  done

  # Validate CHANNELS_REDIS_PASSWORD is set when ASGI_MODE=true
  if [ "$ASGI_MODE" = "true" ]; then
    # Read CHANNELS_REDIS_PASSWORD directly without eval to avoid injection.
    CHANNELS_REDIS_PASSWORD=$(grep -E '^CHANNELS_REDIS_PASSWORD=' .env.secrets 2>/dev/null | cut -d'=' -f2- || true)
    if [ -z "${CHANNELS_REDIS_PASSWORD:-}" ]; then
      echo "❌ ERROR: ASGI_MODE=true requires CHANNELS_REDIS_PASSWORD in .env.secrets."
      echo "   Add: CHANNELS_REDIS_PASSWORD=<strong_password> to .env.secrets"
      exit 1
    fi
  fi

fi

echo "🚀 Launching Django Celery Platform"
echo "   Deploy Mode:       $MODE"
echo "   Broker Strategy:   $BROKER_MODE"
echo "   Worker Mode:       $WORKER_MODE"
echo "   Server Profile:    $SERVER_PROFILE"
echo "   Code Source:       $CODE_SOURCE"
echo "   ASGI / WebSocket:  $ASGI_MODE"
echo "   Project Config:    $PROJECT_PROFILE"
echo "--------------------------------------------------------"

# ── Code-source compose fragment ─────────────────────────────
# Selects the right volume/mount overlay based on CODE_SOURCE.
# Each overlay adds /app mounts to the services that need code.
# image and pip need no overlay (image: code is in the image;
#                                pip: pip install puts code in site-packages).
CODE_SOURCE_WORKERS_FLAG=""
CODE_SOURCE_DUAL_FLAG=""
CODE_SOURCE_ASGI_FLAG=""
CODE_SOURCE_KAFKA_FLAG=""

case "${CODE_SOURCE}" in
  bind)
    CODE_SOURCE_WORKERS_FLAG="-f components/workers/docker-compose.workers.code-bind.yml"
    [ "$WORKER_MODE" = "dual" ] && \
      CODE_SOURCE_DUAL_FLAG="-f components/workers/docker-compose.dual-workers.code-bind.yml"
    [ "$ASGI_MODE" = "true" ] && \
      CODE_SOURCE_ASGI_FLAG="-f components/workers/docker-compose.asgi.code-bind.yml"
    [ "$BROKER_MODE" = "kafka" ] && \
      CODE_SOURCE_KAFKA_FLAG="-f components/workers/docker-compose.kafka-workers.code-bind.yml"
    ;;
  volume)
    CODE_SOURCE_WORKERS_FLAG="-f components/workers/docker-compose.workers.code-volume.yml"
    [ "$WORKER_MODE" = "dual" ] && \
      CODE_SOURCE_DUAL_FLAG="-f components/workers/docker-compose.dual-workers.code-volume.yml"
    [ "$ASGI_MODE" = "true" ] && \
      CODE_SOURCE_ASGI_FLAG="-f components/workers/docker-compose.asgi.code-volume.yml"
    [ "$BROKER_MODE" = "kafka" ] && \
      CODE_SOURCE_KAFKA_FLAG="-f components/workers/docker-compose.kafka-workers.code-volume.yml"
    ;;
  git)
    CODE_SOURCE_WORKERS_FLAG="-f components/workers/docker-compose.workers.code-git.yml"
    [ "$WORKER_MODE" = "dual" ] && \
      CODE_SOURCE_DUAL_FLAG="-f components/workers/docker-compose.dual-workers.code-git.yml"
    [ "$ASGI_MODE" = "true" ] && \
      CODE_SOURCE_ASGI_FLAG="-f components/workers/docker-compose.asgi.code-git.yml"
    [ "$BROKER_MODE" = "kafka" ] && \
      CODE_SOURCE_KAFKA_FLAG="-f components/workers/docker-compose.kafka-workers.code-git.yml"
    ;;
  image|pip)
    # No volume overlay needed — code arrives via image build or pip install.
    ;;
esac

# ── ASGI compose fragment ─────────────────────────────────────
ASGI_COMPOSE_FLAG=""
if [ "$ASGI_MODE" = "true" ]; then
  ASGI_COMPOSE_FLAG="-f components/workers/docker-compose.asgi.yml"
fi

# ── Dual-worker compose fragment ─────────────────────────────
DUAL_WORKER_COMPOSE_FLAG=""
if [ "$WORKER_MODE" = "dual" ]; then
  DUAL_WORKER_COMPOSE_FLAG="-f components/workers/docker-compose.dual-workers.yml -f core/modes/dual-workers.yml"
fi

# ── Kafka-worker compose fragment ────────────────────────────
KAFKA_COMPOSE_FLAG=""
if [ "$BROKER_MODE" = "kafka" ]; then
  KAFKA_COMPOSE_FLAG="-f components/workers/docker-compose.kafka-workers.yml -f core/modes/kafka-broker.yml"
fi

# ── Build the base compose command ───────────────────────────
# --project-directory is pinned to REPO_ROOT because docker compose
# resolves relative volume paths (./prometheus, ./templates, etc.) against
# the directory of the FIRST -f file (components/brokers/) by default, not
# against each individual fragment's own directory or the cwd. Every
# relative path below is written relative to REPO_ROOT to match.
COMPOSE_CMD="docker compose \
  --project-directory ${REPO_ROOT} \
  -f components/brokers/docker-compose.brokers.yml \
  -f components/gateway/docker-compose.gateway.yml \
  -f components/workers/docker-compose.workers.yml \
  ${CODE_SOURCE_WORKERS_FLAG} \
  ${ASGI_COMPOSE_FLAG} \
  ${CODE_SOURCE_ASGI_FLAG} \
  ${DUAL_WORKER_COMPOSE_FLAG} \
  ${CODE_SOURCE_DUAL_FLAG} \
  ${KAFKA_COMPOSE_FLAG} \
  ${CODE_SOURCE_KAFKA_FLAG} \
  -f components/observability/docker-compose.monitoring.yml \
  -f core/modes/${MODE}.yml \
  --env-file .docker.env \
  --env-file ${PROJECT_PROFILE} \
  --env-file core/profiles/sizing.${SERVER_PROFILE}.env \
  --env-file components/workers/strategies/broker.${BROKER_MODE}.env \
  --env-file components/workers/strategies/worker.${WORKER_MODE}.env \
  --env-file .env.secrets"

# ── Ensure the shared broker network exists ───────────────────
# components/workers/*.yml and components/workers/docker-compose.dual-workers.yml
# declare celery-broker-net as `external: true`. When merged with
# components/brokers/docker-compose.brokers.yml (which defines the network),
# docker compose's merge resolves the network as external — so on a first
# run, "up" fails with "network celery-broker-net declared as external, but
# could not be found" because nothing ever creates it. Create it ourselves,
# idempotently, before bringing up the stack.
if [ "$COMMAND" = "up" ] || [ "$COMMAND" = "restart" ]; then
  NETWORK_SUBNET=$(grep -E '^CELERY_NETWORK_SUBNET=' .docker.env 2>/dev/null | cut -d= -f2-)
  NETWORK_SUBNET="${NETWORK_SUBNET:-10.220.200.0/24}"
  if ! docker network inspect celery-broker-net >/dev/null 2>&1; then
    echo "Creating docker network celery-broker-net (${NETWORK_SUBNET})..."
    docker network create --driver bridge --subnet "${NETWORK_SUBNET}" celery-broker-net
  else
    # Subnet drift check — an existing network with a different subnet means
    # the configuration changed after creation (or another stack owns the
    # name). Containers would silently join the OLD subnet, breaking every
    # IP-based allowlist (nginx stub_status, Prometheus scrape rules).
    EXISTING_SUBNET=$(docker network inspect celery-broker-net \
      --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)
    if [ -n "$EXISTING_SUBNET" ] && [ "$EXISTING_SUBNET" != "$NETWORK_SUBNET" ]; then
      echo "❌ ERROR: network celery-broker-net exists with subnet ${EXISTING_SUBNET},"
      echo "   but configuration requests ${NETWORK_SUBNET} (CELERY_NETWORK_SUBNET in .docker.env)."
      echo "   Fix: ./core/up.sh down && docker network rm celery-broker-net"
      echo "   then re-run this command to recreate it on the configured subnet."
      exit 1
    fi
  fi
fi

# ── Post-launch health summary ────────────────────────────────
# Probes the published ports so the user gets an immediate green/red
# overview instead of having to run docker ps + curl manually.
# Uses bash's /dev/tcp (up.sh is bash) — no nc/curl dependency.
_env_default() {
  # _env_default KEY DEFAULT — read KEY from .docker.env, else DEFAULT
  local v
  v=$(grep -E "^$1=" .docker.env 2>/dev/null | tail -1 | cut -d= -f2-)
  echo "${v:-$2}"
}

_check_port() {
  if (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then
    exec 3>&- 3<&-
    echo "  ✓ $2 → 127.0.0.1:$1"
  else
    echo "  ✗ $2 NOT responding on :$1"
    _HEALTH_FAILED=1
  fi
}

post_launch_summary() {
  echo ""
  echo "=== Platform started. Probing published ports... ==="
  sleep 5
  _HEALTH_FAILED=0
  _check_port "$(_env_default NGINX_HTTPS_PORT 8443)" "Nginx (HTTPS gateway)"
  case "$BROKER_MODE" in
    redis|hybrid) _check_port "$(_env_default FLOWER_PORT_REDIS 5555)" "Flower (Redis)" ;;
  esac
  case "$BROKER_MODE" in
    rabbitmq|hybrid) _check_port "$(_env_default FLOWER_PORT_RABBITMQ 5556)" "Flower (RabbitMQ)" ;;
  esac
  [ "$WORKER_MODE" = "dual" ] && _check_port "$(_env_default FLOWER_PORT_HYBRID 5557)" "Flower (Hybrid)"
  [ "$BROKER_MODE" = "kafka" ] && _check_port "$(_env_default FLOWER_PORT_KAFKA 5558)" "Flower (Kafka)"
  if [ "$MODE" != "minimal" ]; then
    _check_port "$(_env_default PORT_GRAFANA 8300)" "Grafana"
    _check_port "$(_env_default PORT_PROMETHEUS 9090)" "Prometheus"
  fi
  echo ""
  if [ "${_HEALTH_FAILED}" -eq 1 ]; then
    echo "⚠️  Some services are not responding yet. They may still be starting —"
    echo "   re-check in ~30s with: docker ps"
    echo "   For any container that is restarting: docker logs <container-name>"
  else
    echo "✅ All expected ports are answering."
  fi
}

case "$COMMAND" in
  up)
    eval "$COMPOSE_CMD up -d"
    echo "--------------------------------------------------------"
    post_launch_summary
    ;;
  down)
    eval "$COMPOSE_CMD down"
    echo "✅ Stack stopped."
    ;;
  restart)
    eval "$COMPOSE_CMD down"
    eval "$COMPOSE_CMD up -d"
    echo "✅ Stack restarted."
    post_launch_summary
    ;;
  ps)
    eval "$COMPOSE_CMD ps"
    ;;
  logs)
    eval "$COMPOSE_CMD logs -f"
    ;;
  *)
    echo "❌ Unknown command: $COMMAND"
    echo "   Usage: ./core/up.sh [up|down|restart|ps|logs]"
    exit 1
    ;;
esac
