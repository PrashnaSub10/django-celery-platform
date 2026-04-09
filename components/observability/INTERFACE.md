# Observability Component Interface Contract

The Observability component provides project-wide telemetry, alerting, and visualization. It acts as a passive observer of the platform.

## 📥 Consumes (Inputs)
| Environment Variable | Description |
|----------------------|-------------|
| `REDIS_PASSWORD` | Required for Redis Exporter |
| `RABBITMQ_USER` | Required for RabbitMQ Exporter |
| `RABBITMQ_PASSWORD` | Required for RabbitMQ Exporter |
| `GF_SECURITY_ADMIN_PASSWORD` | Master password for Grafana |
| `SLACK_WEBHOOK_URL` | Destination for Alertmanager alerts (Optional) |
| `PROMETHEUS_RETENTION_TIME` | Data retention policy (Default: `15d`) |

## 📤 Exposes (Outputs)
- **`:9090`** — Prometheus Web UI.
- **`:8300`** — Grafana Dashboard UI.
- **`:9093`** — Alertmanager UI.
- **Various Exporters** — `:9121` (Redis), `:9419` (RabbitMQ), `:9100` (Node), `:9113` (Nginx).

## 🕸️ Network State
- **Expects**: `celery-broker-net`.
- **Scrape Strategy**: Actively reaches out to containers via internal hostnames (e.g., `redis-exporter-shared`).
- **External Network**: Configured as `external: true`. Requires Brokers to be started first.

## 🛑 Strict Isolation
- **Passive Failure**: If the Observability component fails, the Brokers, Workers, and Gateway continue to operate normally.
- **Read-Only**: Exporters should have read-only access to broker metrics wherever possible.
- **Resource Constraints**: Strictly limited to ensure monitoring doesn't steal CPU/RAM from the mission-critical workers.
