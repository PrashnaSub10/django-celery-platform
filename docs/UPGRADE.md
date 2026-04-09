# Upgrade Guide

Step-by-step migration guides for upgrading between Django Celery Platform versions.
Read the relevant section before applying any upgrade.

---

## Table of Contents

- [3.0.0 → 3.1.0](#300--310)
- [3.1.0 → Unreleased (3.2.0)](#310--unreleased-320)
- [Pre-Upgrade Checklist (all versions)](#pre-upgrade-checklist-all-versions)
- [Rollback Procedures](#rollback-procedures)

---

## Pre-Upgrade Checklist (all versions)

Run through this list before applying any version upgrade:

1. **Back up your data volumes.**
   ```bash
   docker compose down
   docker run --rm -v redis_data:/data -v $(pwd)/backup:/backup alpine \
     tar czf /backup/redis_data.tar.gz -C /data .
   # Repeat for rabbitmq_data, kafka_data, grafana_data, prometheus_data
   ```

2. **Record your current configuration.**
   ```bash
   cp .docker.env .docker.env.backup
   cp .env.secrets .env.secrets.backup
   cp celery-profile.env celery-profile.env.backup  # if it exists
   ```

3. **Note your current image tags.**
   ```bash
   docker images | grep celery-microservice
   ```

4. **Read the CHANGELOG.md** entry for the target version in full.

5. **Test in a staging environment first** if running in production.

---

## 3.0.0 → 3.1.0

**Release date:** 2026-04

### What changed

| Area | Change | Action required |
|---|---|---|
| **New dimension: `WORKER_MODE`** | `single` (default) / `dual` — dual runs `worker-fast` + `worker-critical` with unified Flower at `:5557` | No action if using defaults. Set `WORKER_MODE=dual` + `BROKER_MODE=hybrid` to opt in. |
| **New dimension: `ASGI_MODE`** | `true` / `false` — enables Daphne + Redis Channel Layer for WebSocket support | No action if using defaults (`false`). Set `ASGI_MODE=true` + add `CHANNELS_REDIS_PASSWORD` to `.env.secrets` to opt in. |
| **Five Docker images** | `Dockerfile.base`, `.full`, `.mssql`, `.pdf`, `.smb` — layered capability images | Rebuild images: `docker compose build`. If you were using a custom single Dockerfile, switch to `celery-microservice:base` or the appropriate capability variant. |
| **`pip` upgrade** | `pip==24.0` → `pip==25.1` in `Dockerfile.base` | Rebuild base image. No application code changes needed. |
| **Non-root workers** | All worker containers now run as `celery` user | If your tasks write to the filesystem, ensure the target directories are writable by the `celery` user or use a volume mount. |
| **Flower ports** | Added `FLOWER_PORT_HYBRID=5557` | Add to `.docker.env` if not present. Default is `5557`. |
| **Reference config modules** | `components/workers/config/` added: `broker_settings.py`, `celery_config.py`, `celery_hybrid.py`, `django_celery_integration.py`, `path_utils.py` | Copy the relevant modules into your Django project's `config/` directory. See `docs/DEVELOPER_GUIDE.md`. |
| **`up.sh` validation** | Now validates all dimension values against allow-lists before constructing file paths | If you have custom scripts calling `up.sh`, ensure dimension values are from the documented set. |
| **`from __future__ import annotations` removed** | Not needed on Python 3.13 | Remove from your own Celery config files if you copied them from pre-3.1 examples. |

### Step-by-step

1. **Pull the latest code:**
   ```bash
   git pull origin main
   ```

2. **Update `.docker.env`** — add new variables (compare with `.docker.env` in the new version):
   ```env
   # New in 3.1.0
   FLOWER_PORT_HYBRID=5557
   ```

3. **Rebuild images:**
   ```bash
   docker compose build --no-cache
   ```

4. **Run `init-secrets.sh`** if you haven't already (idempotent — won't overwrite existing secrets):
   ```bash
   ./init-secrets.sh
   ```

5. **Restart the stack:**
   ```bash
   MODE=standard BROKER_MODE=redis ./core/up.sh restart
   ```

6. **Verify:**
   ```bash
   docker ps                        # All containers healthy
   curl -s http://localhost:5555/    # Flower Redis
   curl -s http://localhost:9090/    # Prometheus
   ```

### Breaking changes

> [!WARNING]
> **Non-root worker containers.** If your Celery tasks write files to paths
> inside the container (e.g. `/app/reports/`), the `celery` user must have
> write permissions. Fix: use a volume mount, or `chown` the directory in
> your Dockerfile.

> [!WARNING]
> **`pip==25.1` upgrade.** Some pinned dependencies may resolve differently.
> If you use a `requirements.txt` with exact pins, test thoroughly.

---

## 3.1.0 → Unreleased (3.2.0)

**Status:** Unreleased — upgrading to this version means tracking `main` branch.

### What changed

| Area | Change | Action required |
|---|---|---|
| **New dimension: `CODE_SOURCE`** | `bind` (default) / `image` / `volume` / `git` / `pip` — decouples code delivery from bind-mount assumption | No action if using defaults (`bind`). Review `docs/DEVELOPER_GUIDE.md` Step 1.5 for other modes. |
| **New dimension: `BROKER_MODE=kafka`** | Kafka as a third broker lane via `confluentkafka` transport | No action if not using Kafka. Set `BROKER_MODE=kafka` + `WORKER_MODE=single` to opt in. |
| **Bind-mounts removed from base compose** | `docker-compose.workers.yml`, `docker-compose.dual-workers.yml`, `docker-compose.asgi.yml` no longer contain `/app` bind-mounts — code delivery is now via overlay files | **Critical:** If you had custom volume overrides depending on the bind-mount in the base compose, they will break. Use `CODE_SOURCE=bind` (handled by `up.sh` automatically) or update your overrides. |
| **9 new compose overlay files** | `docker-compose.*.code-{bind,volume,git}.yml` for workers, dual-workers, ASGI | Automatically loaded by `up.sh`. No manual `-f` flags needed. |
| **3 Kafka compose overlay files** | `docker-compose.kafka-workers.code-{bind,volume,git}.yml` | Automatically loaded by `up.sh`. No manual `-f` flags needed. |
| **`docker-entrypoint.sh` updated** | CODE_SOURCE dispatch block added as first action | If you have a custom entrypoint, merge the CODE_SOURCE block from the new version. |
| **`Dockerfile.base` updated** | `git` added to system packages; `/app` owned by `celery` user | Rebuild base image. |
| **`.celery-profile.env.example` updated** | Full CODE_SOURCE documentation and variables | Update your `celery-profile.env` if using one. New variables: `CODE_SOURCE`, `APP_GIT_URL`, `APP_GIT_BRANCH`, `APP_VOLUME_NAME`, `APP_PIP_PACKAGE`. |
| **New dimension: `RESULT_BACKEND`** | `redis` (default) / `django-db` / `postgres` / `none` — configurable result backend | No action if using defaults (`redis`). Set `RESULT_BACKEND=django-db` if using `django-celery-results`. |
| **`PORT_*` variables** | All host-side ports now overridable via `.docker.env` | No action if using defaults. Set `PORT_GRAFANA=9300` (etc.) in `.docker.env` to remap any conflicting port. |
| **`broker_settings.py` updated** | New `get_result_backend()` function; `redis_backend_url()` still exists but is no longer called directly by config modules | If you imported `redis_backend_url` directly, your code still works. For new code, prefer `get_result_backend()`. |
| **Kafka broker** | `celery-kafka-shared` container (Bitnami Kafka 3.9, KRaft mode), `worker-kafka`, `flower-kafka` (:5558), `celery-beat-kafka` | Review `.docker.env` for new Kafka variables (`KAFKA_HOST`, `KAFKA_PORT`, `KAFKA_NUM_PARTITIONS`, etc.). |
| **`confluent-kafka==2.6.1`** | Added to `requirements/core.txt` | Automatically included in image rebuild. No action needed unless you have conflicting package versions. |

### Step-by-step

1. **Pull the latest code:**
   ```bash
   git pull origin main
   ```

2. **Update `.docker.env`** — add new sections (compare with the new `.docker.env`):
   ```env
   # New: Kafka configuration
   KAFKA_HOST=celery-kafka-shared
   KAFKA_PORT=9092
   KAFKA_NUM_PARTITIONS=3
   KAFKA_LOG_RETENTION_HOURS=168
   KAFKA_MESSAGE_MAX_BYTES=1048576
   CELERY_KAFKA_WORKER_CONCURRENCY=4
   CELERY_KAFKA_WORKER_POOL=prefork
   CELERY_KAFKA_WORKER_PREFETCH_MULTIPLIER=1
   CELERY_KAFKA_WORKER_MAX_TASKS_PER_CHILD=500
   FLOWER_PORT_KAFKA=5558

   # New: Result backend
   RESULT_BACKEND=redis

   # New: Host port overrides (all optional — defaults match existing ports)
   PORT_REDIS=6379
   PORT_RABBITMQ=5672
   PORT_RABBITMQ_MGMT=15672
   PORT_KAFKA=9092
   PORT_PROMETHEUS=9090
   PORT_GRAFANA=8300
   PORT_ALERTMANAGER=9093
   PORT_REDIS_EXPORTER=9121
   PORT_RABBITMQ_EXPORTER=9419
   PORT_CELERY_EXPORTER_REDIS=9808
   PORT_CELERY_EXPORTER_RABBITMQ=9809
   PORT_NODE_EXPORTER=9100
   PORT_NGINX_EXPORTER=9113
   ```

3. **Update `celery-profile.env`** — add CODE_SOURCE variables:
   ```env
   # New: CODE_SOURCE (default: bind — existing behaviour)
   CODE_SOURCE=bind
   APP_PATH=/path/to/your/django-project
   ```

4. **Update your Celery config modules:**

   If you copied `broker_settings.py` into your Django project, update it from
   `components/workers/config/broker_settings.py`. Key addition: `get_result_backend()`.

   If you copied `celery_config.py`, `celery_hybrid.py`, or
   `django_celery_integration.py`, update them — they now use
   `get_result_backend()` instead of `redis_backend_url()` / `"rpc://"`.

5. **Rebuild images:**
   ```bash
   docker compose build --no-cache
   ```

6. **Restart the stack:**
   ```bash
   MODE=standard BROKER_MODE=redis ./core/up.sh restart
   ```

7. **Verify:**
   ```bash
   docker ps                        # All containers healthy
   curl -s http://localhost:5555/    # Flower Redis
   curl -s http://localhost:9090/    # Prometheus
   curl -s http://localhost:8300/    # Grafana
   ```

### Breaking changes

> [!CAUTION]
> **Bind-mounts removed from base compose files.** If you have custom compose
> override files that depend on the `/app` bind-mount being in
> `docker-compose.workers.yml`, they will break. The bind-mount is now in
> `docker-compose.workers.code-bind.yml`, loaded automatically by `up.sh`
> when `CODE_SOURCE=bind`.

> [!WARNING]
> **RabbitMQ app result backend changed.** In 3.1.0, `app_rabbitmq` used
> `backend="rpc://"`. In the unreleased version, it uses `get_result_backend()`,
> which defaults to Redis DB 1. If you relied on RPC-style result retrieval
> (calling `.get()` directly from the producer), this still works — Redis
> result backend supports the same `.get()` API. If you explicitly need RPC
> backend, set `RESULT_BACKEND=redis` (the default) which provides equivalent
> functionality with better persistence.

> [!IMPORTANT]
> **If you use `BROKER_MODE=kafka`:** You must use `WORKER_MODE=single`.
> `BROKER_MODE=kafka` + `WORKER_MODE=dual` is not supported — `up.sh`
> will exit with an error.

---

## Rollback Procedures

### Quick rollback (any version)

1. **Stop the current stack:**
   ```bash
   ./core/up.sh down
   ```

2. **Restore your backed-up configuration:**
   ```bash
   cp .docker.env.backup .docker.env
   cp .env.secrets.backup .env.secrets
   cp celery-profile.env.backup celery-profile.env  # if applicable
   ```

3. **Check out the previous version:**
   ```bash
   git checkout v3.1.0   # or whatever version you're rolling back to
   ```

4. **Rebuild images from the previous version:**
   ```bash
   docker compose build --no-cache
   ```

5. **Restore data volumes** (if needed):
   ```bash
   docker run --rm -v redis_data:/data -v $(pwd)/backup:/backup alpine \
     tar xzf /backup/redis_data.tar.gz -C /data
   ```

6. **Restart:**
   ```bash
   ./core/up.sh up
   ```

### Partial rollback (keep data, revert config)

If the upgrade broke configuration but data is fine:

1. Restore config files from backup.
2. Rebuild images from the target version's code.
3. Restart — existing volumes will be reused.

> [!NOTE]
> Data volumes (Redis, RabbitMQ, Kafka, Grafana, Prometheus) are version-independent.
> Rolling back the platform code does not affect stored task results, broker messages,
> or dashboards unless the upstream images introduced a breaking schema change.

---

**Version**: 3.1.0
**Project**: django-celery-platform
**Architecture**: Composable Monorepo Component Model
**Last Updated**: 2026-04
**License**: MIT — see LICENSE in the repository root
