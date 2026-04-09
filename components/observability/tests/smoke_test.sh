#!/usr/bin/env bash
# ==========================================================
# Observability Smoke Test
# ==========================================================
# Validates Prometheus rules and Grafana provisioning.
# ==========================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "[1/2] Validating Prometheus Alert Rules..."
if docker run --rm \
    -v "$(pwd)/prometheus:/etc/prometheus:ro" \
    --entrypoint /bin/promtool \
    prom/prometheus:latest \
    check rules /etc/prometheus/alert_rules.yml; then
    echo "✅ Alert rules syntax OK."
else
    echo "❌ Alert rules validation failed."
    exit 1
fi

echo "[2/2] Checking Grafana provisioning structure and dashboard syntax..."
ls grafana/provisioning/dashboards > /dev/null
ls grafana/provisioning/datasources > /dev/null

DASHBOARD_ERRORS=0
for f in grafana/provisioning/dashboards/*.json; do
    [ -f "$f" ] || continue
    if python3 -c "import json,sys; json.load(open('$f'))" 2>/dev/null; then
        echo "   ✅ $(basename "$f")"
    else
        echo "   ❌ $(basename "$f") — invalid JSON"
        DASHBOARD_ERRORS=$((DASHBOARD_ERRORS + 1))
    fi
done

if [ "$DASHBOARD_ERRORS" -gt 0 ]; then
    echo "❌ $DASHBOARD_ERRORS dashboard(s) have invalid JSON."
    exit 1
fi
echo "✅ Grafana provisioning structure OK."

echo "All observability smoke tests passed."
