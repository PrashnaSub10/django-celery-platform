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

  # Validate required variables per CODE_SOURCE mode
  case "$CODE_SOURCE" in
    bind)
      if [ -z "${APP_PATH:-}" ]; then
        echo "❌ ERROR: CODE_SOURCE=bind requires APP_PATH."
        echo "   Set APP_PATH=/absolute/path/to/your/django-project in: $PROJECT_PROFILE"
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
COMPOSE_CMD="docker compose \
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

case "$COMMAND" in
  up)
    eval "$COMPOSE_CMD up -d"
    echo "--------------------------------------------------------"
    echo "✅ Stack is up. Check status: docker ps"
    ;;
  down)
    eval "$COMPOSE_CMD down"
    echo "✅ Stack stopped."
    ;;
  restart)
    eval "$COMPOSE_CMD down"
    eval "$COMPOSE_CMD up -d"
    echo "✅ Stack restarted."
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
