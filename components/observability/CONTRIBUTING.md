# Contributing to Observability Component

This module handles the Prometheus TSDB, Grafana provisioning, and Alertmanager routing rules.

## Local Testing Loop

You can validate monitoring logic without any real traffic.

1. **Verify Alert Rules:**
   Use the `promtool` (included in the Prometheus docker image) to validate your YAML rules:
   ```bash
   docker run --rm -v $(pwd)/components/observability/prometheus:/etc/prometheus prom/prometheus:latest promtool check rules /etc/prometheus/alert_rules.yml
   ```

2. **Isolated Boot:**
   ```bash
   docker network create celery-broker-net || true
   # Use dummy passwords for exporters to start
   GF_SECURITY_ADMIN_PASSWORD=admin REDIS_PASSWORD=dummy \
   docker compose -f components/observability/docker-compose.monitoring.yml up -d
   ```

3. **Check Connectivity:**
   Ensure Grafana can reach Prometheus at `http://prometheus-shared:9090`.

## Development Guidelines
- **Provisioning over Manual UI**: Never create dashboards manually in the Grafana UI. Always add them to `grafana/provisioning/dashboards/*.json` for version control.
- **Exporter Mapping**: If you add a new service to the platform, ensure you add the corresponding Prometheus scrape job to `prometheus.yml.template`.
- **Alert Severity**: Use `warning` for things needing attention during business hours and `critical` only for things needing immediate wake-up.
