#!/usr/bin/env bash
# ==========================================================
# Brokers Smoke Test
# ==========================================================
# Validates Redis and RabbitMQ can start without workers.
# ==========================================================

set -euo pipefail

# Always run from the component root so relative paths resolve correctly
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Teardown on any exit (pass or fail) so containers never leak
trap 'docker compose -f docker-compose.brokers.yml down -v 2>/dev/null || true' EXIT

# 1. Supply contract requirements
export REDIS_PASSWORD=smokepass
export RABBITMQ_USER=smokeuser
export RABBITMQ_PASSWORD=smokepass

# 2. Boot the stack — Redis and RabbitMQ only.
# Kafka (bitnami/kafka:3.9, ~800 MB) is not tested here; pulling it in CI is slow
# and its startup is irrelevant to the broker contract this test validates.
echo "[1/3] booting brokers isolated..."
docker compose -f docker-compose.brokers.yml up -d redis rabbitmq

# Wait for RabbitMQ management API with a timeout instead of a fixed sleep
echo "[2/3] Waiting for RabbitMQ management API (timeout: 60s)..."
for i in $(seq 1 30); do
    if curl -s -u smokeuser:smokepass http://localhost:15672/api/overview 2>/dev/null | grep -q "rabbitmq_version"; then
        echo "   RabbitMQ ready after ~$((i * 2))s."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "❌ RabbitMQ did not become ready within 60s."
        docker logs celery-rabbitmq-shared
        exit 1
    fi
    sleep 2
done

# 3. Test the interface
echo "[3/3] validating endpoints..."

# Test 1: Redis ping
if docker exec celery-redis-shared redis-cli -a smokepass ping | grep -q "PONG"; then
    echo "✅ Redis is responsive."
else
    echo "❌ Redis failed." && docker logs celery-redis-shared && exit 1
fi

# Test 2: RabbitMQ management API
if curl -s -u smokeuser:smokepass http://localhost:15672/api/overview | grep -q "rabbitmq_version"; then
    echo "✅ RabbitMQ Management API accessible."
else
    echo "❌ RabbitMQ failed." && docker logs celery-rabbitmq-shared && exit 1
fi

echo "All broker smoke tests passed."
