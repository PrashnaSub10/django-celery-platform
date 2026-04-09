#!/bin/bash
# ============================================================
# init-secrets.sh — Secure Secrets Generator
# ============================================================
# Generates a .env.secrets file with strong random passwords.
# Run once on a fresh deployment. Delete the file and re-run
# to rotate all credentials.
# ============================================================

SECRETS_FILE=".env.secrets"

if [ -f "$SECRETS_FILE" ]; then
    echo "$SECRETS_FILE already exists. Skipping generation."
    echo "   Delete it and re-run to rotate all credentials."
    exit 0
fi

# Verify openssl is available before attempting to generate secrets.
if ! command -v openssl > /dev/null 2>&1; then
    echo "ERROR: openssl is required but not found."
    echo "   Install it with: sudo apt install openssl"
    exit 1
fi

echo "Generating strong random passwords..."

REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '\n\r/=+' | cut -c1-32)
RABBITMQ_PASSWORD=$(openssl rand -base64 24 | tr -d '\n\r/=+' | cut -c1-32)
CHANNELS_REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '\n\r/=+' | cut -c1-32)
FLOWER_PASSWORD=$(openssl rand -base64 24 | tr -d '\n\r/=+' | cut -c1-32)
GRAFANA_PASSWORD=$(openssl rand -base64 24 | tr -d '\n\r/=+' | cut -c1-32)

cat > "$SECRETS_FILE" <<SECRETS
# ── Broker Credentials ──────────────────────────────────────
REDIS_PASSWORD=${REDIS_PASSWORD}
RABBITMQ_USER=admin
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}

# ── ASGI / Django Channels (only needed when ASGI_MODE=true) ─
# Isolated Redis instance for Channel Layer — must differ from
# REDIS_PASSWORD because Channel Layer requires noeviction policy.
CHANNELS_REDIS_PASSWORD=${CHANNELS_REDIS_PASSWORD}

# ── Flower Dashboard ────────────────────────────────────────
FLOWER_USER=admin
FLOWER_PASSWORD=${FLOWER_PASSWORD}

# ── Grafana ─────────────────────────────────────────────────
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}

# ── Kafka (only needed when BROKER_MODE=kafka with SASL auth) ─
# Dev mode uses PLAINTEXT (no auth). For production with SASL:
# KAFKA_SASL_USERNAME=admin
# KAFKA_SASL_PASSWORD=<replace_with_kafka_sasl_password>

# ── Alerting Integrations (fill in before deploying) ────────
# Placeholder values are intentionally non-functional.
# Replace with real values before deploying.
SLACK_WEBHOOK_URL=<replace_with_slack_webhook_url>
PAGERDUTY_INTEGRATION_KEY=<replace_with_pagerduty_key>

# ── Email Credentials ───────────────────────────────────────
EMAIL_HOST_PASSWORD=<change_me>

# ── Media Volume Path ───────────────────────────────────────
MEDIA_VOLUME_PATH=/mnt/media
SECRETS

chmod 600 "$SECRETS_FILE"

echo "$SECRETS_FILE created with strong random passwords."
echo ""
echo "Before deploying, edit $SECRETS_FILE and fill in:"
echo "   - SLACK_WEBHOOK_URL"
echo "   - PAGERDUTY_INTEGRATION_KEY"
echo "   - EMAIL_HOST_PASSWORD"
echo "   - MEDIA_VOLUME_PATH (if not /mnt/media)"
echo ""
echo "   CHANNELS_REDIS_PASSWORD is auto-generated."
echo "   Only needed when launching with ASGI_MODE=true."
