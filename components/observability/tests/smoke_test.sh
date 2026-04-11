#!/usr/bin/env bash
# ==========================================================
# Observability Smoke Test
# ==========================================================
# [1/3] Static: Prometheus alert rule syntax (promtool)
# [2/3] Static: Grafana provisioning JSON validity
# [3/3] Live:   Prometheus and Grafana health endpoints
# ==========================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Shared wait helper — avoids a fixed sleep
_wait_for_http() {
    local url="$1" label="$2" max="${3:-20}" delay="${4:-3}"
    for i in $(seq 1 "$max"); do
        if curl -sf "$url" > /dev/null 2>&1; then
            echo "  $label healthy after ~$((i * delay))s."
            return 0
        fi
        sleep "$delay"
    done
    echo "  FAIL: $label did not become healthy within $((max * delay))s."
    return 1
}

echo "[1/3] Validating Prometheus alert rules..."
if docker run --rm \
    -v "$(pwd)/prometheus:/etc/prometheus:ro" \
    --entrypoint /bin/promtool \
    prom/prometheus:latest \
    check rules /etc/prometheus/alert_rules.yml; then
    echo "  Alert rules syntax OK."
else
    echo "FAIL: Alert rules validation failed."
    exit 1
fi

echo "[2/3] Validating Grafana provisioning structure and dashboard JSON..."
ls grafana/provisioning/dashboards > /dev/null
ls grafana/provisioning/datasources > /dev/null

DASHBOARD_ERRORS=0
for f in grafana/provisioning/dashboards/*.json; do
    [ -f "$f" ] || continue
    if python3 -c "import json,sys; json.load(open('$f'))" 2>/dev/null; then
        echo "  $(basename "$f") — JSON OK."
    else
        echo "  FAIL: $(basename "$f") — invalid JSON"
        DASHBOARD_ERRORS=$((DASHBOARD_ERRORS + 1))
    fi
done

if [ "$DASHBOARD_ERRORS" -gt 0 ]; then
    echo "FAIL: $DASHBOARD_ERRORS dashboard(s) have invalid JSON."
    exit 1
fi
echo "  Grafana provisioning structure OK."

echo "[3/3] Live health check: Prometheus and Grafana..."

# Supply defaults so the test runs without a .docker.env present
export METRICS_TARGET_HOST="${METRICS_TARGET_HOST:-127.0.0.1}"
export METRICS_TARGET_PORT="${METRICS_TARGET_PORT:-9845}"
export PROMETHEUS_RETENTION_TIME="${PROMETHEUS_RETENTION_TIME:-1d}"
export GF_SECURITY_ADMIN_PASSWORD="${GF_SECURITY_ADMIN_PASSWORD:-smokepass}"
export PORT_PROMETHEUS="${PORT_PROMETHEUS:-9090}"
export PORT_GRAFANA="${PORT_GRAFANA:-8300}"

# Network must exist for the monitoring compose to attach to
docker network create celery-broker-net 2>/dev/null || true

trap 'docker compose -f docker-compose.monitoring.yml down -v 2>/dev/null || true
      docker network rm celery-broker-net 2>/dev/null || true' EXIT

docker compose -f docker-compose.monitoring.yml up -d prometheus grafana

_wait_for_http "http://localhost:${PORT_PROMETHEUS}/-/healthy" "Prometheus" 20 3 || {
    docker compose -f docker-compose.monitoring.yml logs prometheus
    exit 1
}

_wait_for_http "http://localhost:${PORT_GRAFANA}/api/health" "Grafana" 20 3 || {
    docker compose -f docker-compose.monitoring.yml logs grafana
    exit 1
}

echo ""
echo "All observability smoke tests passed."
# Teardown is handled by the trap on EXIT
