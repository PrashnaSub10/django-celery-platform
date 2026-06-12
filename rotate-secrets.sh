#!/usr/bin/env bash
# ============================================================
# rotate-secrets.sh — Graceful one-at-a-time credential rotation
# ============================================================
# init-secrets.sh rotation model is "delete the file, restart
# everything" — atomic credential replacement that breaks every
# running container simultaneously. This script rotates ONE
# credential at a time against the LIVE broker, updates
# .env.secrets, restarts only the consumers, and verifies.
#
# Usage:
#   ./rotate-secrets.sh redis      # rotate REDIS_PASSWORD
#   ./rotate-secrets.sh rabbitmq   # rotate RABBITMQ_PASSWORD
#
# NOTE: Redis rotation via CONFIG SET does not persist across a
# Redis container restart by itself — the new password is also
# written to .env.secrets, which the compose command line reads,
# so the next 'up' uses the same new password. No window exists
# where the two disagree except between steps 1 and 2 (~ms).
# ============================================================

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SECRETS_FILE=".env.secrets"
[ -f "$SECRETS_FILE" ] || { echo "❌ $SECRETS_FILE not found. Run ./init-secrets.sh first."; exit 1; }

_gen() { openssl rand -base64 24 | tr -d '\n\r/=+' | cut -c1-32; }

_read_secret() { grep -E "^$1=" "$SECRETS_FILE" | tail -1 | cut -d= -f2-; }

_write_secret() {
  # in-place update preserving the rest of the file
  if grep -qE "^$1=" "$SECRETS_FILE"; then
    sed -i.rotate-bak "s|^$1=.*|$1=$2|" "$SECRETS_FILE"
  else
    echo "$1=$2" >> "$SECRETS_FILE"
  fi
}

rotate_redis() {
  local old new
  old=$(_read_secret REDIS_PASSWORD)
  [ -n "$old" ] || { echo "❌ REDIS_PASSWORD not present in $SECRETS_FILE"; exit 1; }
  new=$(_gen)

  echo "→ 1/4 Setting new password on live Redis (old auth)..."
  docker exec celery-redis-shared redis-cli -a "$old" --no-auth-warning \
    CONFIG SET requirepass "$new" >/dev/null

  echo "→ 2/4 Updating $SECRETS_FILE..."
  _write_secret REDIS_PASSWORD "$new"

  echo "→ 3/4 Restarting Redis consumers (workers/beat/flower — not the broker)..."
  docker ps --format '{{.Names}}' | grep -E 'worker-fast|flower-redis|beat' | \
    xargs -r docker restart >/dev/null

  echo "→ 4/4 Verifying new credential..."
  docker exec celery-redis-shared redis-cli -a "$new" --no-auth-warning PING | grep -q PONG || {
    echo "❌ Verification failed — old password restored in $SECRETS_FILE.rotate-bak"; exit 1; }
  rm -f "$SECRETS_FILE.rotate-bak"
  echo "✅ REDIS_PASSWORD rotated."
}

rotate_rabbitmq() {
  local user old new
  user=$(_read_secret RABBITMQ_USER); user="${user:-admin}"
  old=$(_read_secret RABBITMQ_PASSWORD)
  [ -n "$old" ] || { echo "❌ RABBITMQ_PASSWORD not present in $SECRETS_FILE"; exit 1; }
  new=$(_gen)

  echo "→ 1/4 Changing password on live RabbitMQ..."
  docker exec celery-rabbitmq-shared rabbitmqctl change_password "$user" "$new" >/dev/null

  echo "→ 2/4 Updating $SECRETS_FILE..."
  _write_secret RABBITMQ_PASSWORD "$new"

  echo "→ 3/4 Restarting RabbitMQ consumers..."
  docker ps --format '{{.Names}}' | grep -E 'worker-critical|flower-rabbitmq|flower-hybrid|beat' | \
    xargs -r docker restart >/dev/null

  echo "→ 4/4 Verifying new credential..."
  docker exec celery-rabbitmq-shared rabbitmqctl authenticate_user "$user" "$new" >/dev/null || {
    echo "❌ Verification failed — old password restored in $SECRETS_FILE.rotate-bak"; exit 1; }
  rm -f "$SECRETS_FILE.rotate-bak"
  echo "✅ RABBITMQ_PASSWORD rotated."
}

case "${1:-}" in
  redis)    rotate_redis ;;
  rabbitmq) rotate_rabbitmq ;;
  *)
    echo "Usage: ./rotate-secrets.sh [redis|rabbitmq]"
    echo "Rotates one credential at a time against the live broker."
    exit 1
    ;;
esac
