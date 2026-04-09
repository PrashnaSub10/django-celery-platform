#!/bin/sh
# Submits env variables into Prometheus config prior to launching standard Prometheus
set -e

# The prom/prometheus image uses busybox. `envsubst` is usually not built into it natively as part of gettext.
# Instead, we will use sed if envsubst is missing, or download it dynamically, or use a basic awk.
# Fortunately, busybox has `sed`.

echo "Generating prometheus.yml from template..."

# Use | as the sed delimiter instead of / so that hostnames containing
# forward slashes (e.g. a URL path) do not break the substitution.
sed -e "s|\${METRICS_TARGET_HOST}|${METRICS_TARGET_HOST}|g" \
    -e "s|\${METRICS_TARGET_PORT}|${METRICS_TARGET_PORT}|g" \
    /etc/prometheus/prometheus.yml.template > /etc/prometheus/prometheus.yml

echo "Starting Prometheus..."
exec /bin/prometheus "$@"
