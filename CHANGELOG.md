# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- `BROKER_MODE=kafka` — Kafka as a third broker lane alongside Redis and RabbitMQ:
  - Apache Kafka in KRaft mode (no ZooKeeper dependency) via `bitnami/kafka:3.9`
  - `worker-kafka` — Celery workers consuming from Kafka topics via `confluentkafka` transport
  - `celery-beat-kafka` — dedicated Beat scheduler dispatching periodic tasks to Kafka topics
  - `flower-kafka` at `:5558` — Flower monitoring for Kafka workers
  - `kafka_broker_url()` and `KAFKA_CONF` in `broker_settings.py`
  - `app_kafka` Celery app in `celery_hybrid.py` and `django_celery_integration.py`
  - `platform.streaming_heartbeat` system task for Kafka pipeline verification
  - `WAIT_FOR_KAFKA` readiness check in `docker-entrypoint.sh`
  - `broker.kafka.env` strategy file documenting Kafka trade-offs
  - `core/modes/kafka-broker.yml` — scales down Redis/RabbitMQ workers in Kafka-only mode
  - 3 CODE_SOURCE overlay files for Kafka workers (`code-bind`, `code-volume`, `code-git`)
  - `confluent-kafka==2.6.1` added to `requirements/core.txt`
  - Kafka configuration defaults in `.docker.env` (`KAFKA_HOST`, `KAFKA_PORT`, etc.)
  - `FLOWER_PORT_KAFKA=5558` in `.docker.env`
- Redis stays active as result backend in `BROKER_MODE=kafka` (Kafka does not support
  Celery result storage natively).
- `CODE_SOURCE` dimension — sixth deployment dimension that decouples code delivery from
  the bind-mount assumption, making the platform work for all Django deployment topologies:
  - `bind` (default) — bind-mount `APP_PATH` from the Docker host (systemd, bare metal, local dev)
  - `image` — code baked into `WORKER_IMAGE` at image build time (custom CI/CD images)
  - `volume` — named Docker volume shared with a containerised Django application
  - `git` — `git clone` at container start + `git pull` on restart (cloud, CI/CD, remote)
  - `pip` — `pip install APP_PIP_PACKAGE` at startup (packaged Django apps)
- 9 new compose overlay files — one per `CODE_SOURCE` mode per component group
  (`docker-compose.workers.code-{bind,volume,git}.yml`, `docker-compose.dual-workers.code-{bind,volume,git}.yml`,
  `docker-compose.asgi.code-{bind,volume,git}.yml`). Loaded automatically by `up.sh`.
- `git` added to `Dockerfile.base` system dependencies — required for `CODE_SOURCE=git`.
- `/app` directory ownership transferred to `celery` user in `Dockerfile.base` so that
  `CODE_SOURCE=git` and `CODE_SOURCE=image` can write to `/app` without root.
- `PORT_*` variables — all host-side ports are now overridable via `.docker.env`:
  `PORT_REDIS`, `PORT_RABBITMQ`, `PORT_RABBITMQ_MGMT`, `PORT_KAFKA`, `PORT_PROMETHEUS`,
  `PORT_GRAFANA`, `PORT_ALERTMANAGER`, `PORT_REDIS_EXPORTER`, `PORT_RABBITMQ_EXPORTER`,
  `PORT_CELERY_EXPORTER_REDIS`, `PORT_CELERY_EXPORTER_RABBITMQ`, `PORT_NODE_EXPORTER`,
  `PORT_NGINX_EXPORTER`. Defaults match existing hardcoded values — zero behavioural change.
- `RESULT_BACKEND` dimension — configurable result backend via `RESULT_BACKEND` env var:
  `redis` (default), `django-db`, `postgres`, `none`. New `get_result_backend()` function
  in `broker_settings.py` replaces hardcoded `redis_backend_url()` / `"rpc://"` calls in
  all three Celery config modules.
- `docs/UPGRADE.md` — full migration guide covering 3.0.0 → 3.1.0 → Unreleased, with
  breaking changes, step-by-step instructions, and rollback procedures.
- `runtime/` — runtime abstraction layer with three adapters:
  - `runtime/docker/` — pointer to existing `core/up.sh` (structural consistency)
  - `runtime/podman/` — thin shim (`up.sh`) that swaps `docker`→`podman`, delegates to `core/up.sh`
  - `runtime/kubernetes/helm/` — Helm chart skeleton (Chart.yaml, values.yaml, 14 templates)
    mapping all 6 platform dimensions to Kubernetes-native resources (StatefulSets, Deployments,
    Ingress, HPA/KEDA ScaledObjects, ServiceMonitor, Secrets)
- `docs/ARCHITECTURE_DIAGRAM.md` — comprehensive rewrite: 15 sections, 15 Mermaid diagrams
  covering big picture, 6 dimensions, 3 broker lanes, deploy modes, up.sh flow, compose
  layering, network topology, CODE_SOURCE, component contracts, Docker images, observability
  pipeline, directory structure, usage flows, naming conventions, and security model.

### Changed
- `core/up.sh` — added `CODE_SOURCE` dimension validation and conditional code-source overlay
  selection. `APP_PATH` is now only required when `CODE_SOURCE=bind`.
- `docker-compose.workers.yml`, `docker-compose.dual-workers.yml`, `docker-compose.asgi.yml` —
  bind-mounts removed from base anchors and explicit service overrides. Code delivery is now
  handled exclusively via the code-source overlay files.
- All worker services now receive `CODE_SOURCE`, `APP_GIT_URL`, `APP_GIT_BRANCH`, and
  `APP_PIP_PACKAGE` as environment variables so `docker-entrypoint.sh` can act on them.
- `docker-entrypoint.sh` — added `CODE_SOURCE` handling block as the first action:
  validates the mode and (for `git`) clones or pulls; (for `pip`) installs the package.
- `.celery-profile.env.example` — updated with full `CODE_SOURCE` documentation and variables.
- `docs/DEVELOPER_GUIDE.md` — added Step 1.5: comprehensive CODE_SOURCE guide covering all
  five modes with examples, credential patterns for private repos, and production guidance.
- `docs/README.md`, `README.md` — updated dimension tables to include `CODE_SOURCE`.
- `docker-compose.brokers.yml` — all host-side port bindings now use `${PORT_*:-default}`
  variable substitution (`PORT_REDIS`, `PORT_RABBITMQ`, `PORT_RABBITMQ_MGMT`, `PORT_KAFKA`).
- `docker-compose.monitoring.yml` — all host-side port bindings now use `${PORT_*:-default}`
  variable substitution (`PORT_PROMETHEUS`, `PORT_GRAFANA`, `PORT_ALERTMANAGER`,
  `PORT_REDIS_EXPORTER`, `PORT_RABBITMQ_EXPORTER`, `PORT_CELERY_EXPORTER_REDIS`,
  `PORT_CELERY_EXPORTER_RABBITMQ`, `PORT_NODE_EXPORTER`, `PORT_NGINX_EXPORTER`).
- `celery_config.py`, `celery_hybrid.py`, `django_celery_integration.py` — all three
  config modules now use `get_result_backend()` instead of hardcoded `redis_backend_url()`
  or `"rpc://"`. The RabbitMQ app (`app_rabbitmq`) now uses the same result backend as
  the other apps (defaults to Redis DB 1) instead of `rpc://`.

---

## [3.1.0] — 2026-04

### Added
- `WORKER_MODE=dual` — two independent worker pools (`worker-fast` + `worker-critical`) with a
  unified Flower UI at `:5557` that monitors both pools side by side.
- `worker-hybrid-beat` — single Beat scheduler for `WORKER_MODE=dual`; per-broker Beat is
  scaled to 0 automatically to prevent duplicate task execution.
- `flower-hybrid` container at `:5557` — unified Flower for `WORKER_MODE=dual`.
- `FLOWER_PORT_HYBRID` variable (default `5557`) in `.docker.env`.
- `docker-compose.dual-workers.yml` — loaded automatically when `WORKER_MODE=dual`.
- `core/modes/dual-workers.yml` — scales `celery-beat` to 0 when `WORKER_MODE=dual`.
- `ASGI_MODE=true` — optional Daphne + dedicated Redis Channel Layer for WebSocket support.
- `docker-compose.asgi.yml` — loaded when `ASGI_MODE=true`.
- `CHANNELS_REDIS_PASSWORD` secret — isolated Channel Layer Redis (noeviction policy).
- Five Dockerfiles: `Dockerfile.base`, `.full`, `.mssql`, `.pdf`, `.smb`.
- `components/workers/config/` — reference Celery configuration modules:
  `broker_settings.py`, `celery_config.py`, `celery_hybrid.py`,
  `django_celery_integration.py`, `path_utils.py`.
- `components/workers/strategies/` — `broker.*.env` + `worker.*.env` strategy files.
- `init-secrets.sh` — zero-trust secrets generator (strong random passwords).
- `docs/FAILURE_MODES.md` — platform engineering triage guide.
- `docs/MTLS-SETUP-GUIDE.md` — mTLS certificate lifecycle.
- `docs/DEVELOPER_GUIDE.md` — full Django integration guide.
- `docs/ARCHITECTURE_DIAGRAM.md` — component topology and port mapping.

### Changed
- `Dockerfile.base` — upgraded `pip` pin from `24.0` to `25.1`.
- All worker images now run as non-root `celery` user.
- `core/up.sh` — validates all dimension values against allowlist before constructing
  file paths; exits with a clear error if `WORKER_MODE=dual` is requested without
  `BROKER_MODE=hybrid`.

### Fixed
- `from __future__ import annotations` removed from platform config files (not needed
  on Python 3.13; `str | None` union syntax is native).

---

## [3.0.0] — 2025-12

### Added
- Initial composable monorepo architecture with four autonomous components:
  `brokers`, `gateway`, `workers`, `observability`.
- `MODE` dimension: `minimal` / `standard` / `full`.
- `BROKER_MODE` dimension: `redis` / `rabbitmq` / `hybrid`.
- `SERVER_PROFILE` dimension: `small` / `medium` / `large`.
- `core/up.sh` Smart Launcher.
- Prometheus + Grafana + Alertmanager observability stack (5 auto-provisioned dashboards).
- Nginx TLS termination with mTLS option.
- Per-broker Flower instances (`:5555` Redis, `:5556` RabbitMQ).
- `celery-broker-net` Docker network (`10.220.220.0/24`).
