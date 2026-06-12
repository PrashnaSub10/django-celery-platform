#!/bin/sh
# Renders prometheus.yml from template before launching Prometheus.
# Source files are read from /prometheus-config (directory-mounted from
# ./prometheus/) so individual file mounts — which become empty directories
# on Windows Docker Desktop — are avoided.
set -e

echo "Generating prometheus.yml from template..."

# Use | as the sed delimiter so hostnames with forward slashes do not break
# the substitution. The prom/prometheus image uses busybox which has sed.
sed -e "s|\${METRICS_TARGET_HOST}|${METRICS_TARGET_HOST}|g" \
    -e "s|\${METRICS_TARGET_PORT}|${METRICS_TARGET_PORT}|g" \
    -e "s|\${PROMETHEUS_ENVIRONMENT:-production}|${PROMETHEUS_ENVIRONMENT:-production}|g" \
    /prometheus-config/prometheus.yml.template > /etc/prometheus/prometheus.yml

echo "Starting Prometheus..."
exec /bin/prometheus "$@"
