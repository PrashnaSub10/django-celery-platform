# Django Celery Platform

> **"Deploy once. Choose your stack. Worry no more."**

A composable, production-ready infrastructure platform for running Django + Celery workers with Redis and/or RabbitMQ brokers, full TLS via Nginx, and a complete Prometheus + Grafana observability stack.

Each layer is independently deployable, testable, and contributable.

---

## 1. The Core Philosophy: Composable Dimensions

Instead of one monolithic deployment, you assemble your stack across five independent dimensions:

### Dimension 1: Deploy Mode (`MODE`)
- `minimal` — Redis broker + fast worker only. No RabbitMQ, no monitoring. Running in under 5 minutes.
- `standard` — Adds Prometheus + Grafana + all exporters. See problems before users report them.
- `full` — Adds RabbitMQ, Alertmanager (PagerDuty + Slack), mTLS on Nginx. Production-grade.

### Dimension 2: Broker Strategy (`BROKER_MODE`)
- `redis` — Speed-first. Gevent pool, high concurrency. Best for notifications, cache invalidation, real-time events. Not durable under memory pressure.
- `rabbitmq` — Reliability-first. Solo pool, `acks_late`. Best for payments, audit logs, emails. Tasks survive a worker crash.
- `hybrid` — Both. Fast lane (Redis) + secure vault (RabbitMQ) running simultaneously.

### Dimension 3: Worker Topology (`WORKER_MODE`)
- `single` — One worker pool matched to `BROKER_MODE`. Default. Works with any broker strategy.
- `dual` — Both `worker-fast` (Redis + gevent) and `worker-critical` (RabbitMQ + solo) run simultaneously with a unified Flower UI at `:5557` monitoring both pools. A single `worker-hybrid-beat` replaces the per-broker Beat. **Requires `BROKER_MODE=hybrid`.**

### Dimension 4: Server Profile (`SERVER_PROFILE`)
- `small` — 1–2 CPUs, 2–4GB RAM. Low concurrency.
- `medium` — 4 CPUs, 8GB RAM. Balanced performance.
- `large` — 8+ CPUs, 16GB+ RAM. Massive concurrency (150+ gevent workers).

### Dimension 5: Code Delivery (`CODE_SOURCE`)
How your Django project code reaches the Celery worker containers. The platform works regardless of how Django is deployed:

- `bind` — bind-mount `APP_PATH` from the Docker host. Use for systemd services, bare metal, VMs, and local development.
- `image` — code is already baked into `WORKER_IMAGE` via `COPY`. Use when you build custom worker images in CI/CD. No `APP_PATH` needed.
- `volume` — mount a named Docker volume at `/app`. Use when Django is containerised and shares a volume with the workers.
- `git` — clone `APP_GIT_URL` at container start. Use for cloud deployments or any environment where the host filesystem is unavailable.
- `pip` — `pip install APP_PIP_PACKAGE`. Use when your Django project is published as a PyPI package.

### Dimension 6: Project Configuration (`PROJECT_PROFILE`)
- Your Django project's `celery-profile.env` — sets `CODE_SOURCE`, `CELERY_APP_REDIS`, `WORKER_IMAGE`, queue names, and Django settings.

---

## 2. Quick Start

```bash
# 1. Clone
git clone https://github.com/PrashnaSub10/django-celery-platform
cd django-celery-platform

# 2. Generate secrets
./init-secrets.sh

# 3. Generate TLS certificates (Nginx will not start without these)
./components/gateway/scripts/generate_mtls_certs.sh localhost   # dev/localhost
# ./components/gateway/scripts/generate_mtls_certs.sh yourdomain.com  # production

# 4. Create your project profile
cp .celery-profile.env.example celery-profile.env
# Edit celery-profile.env — set APP_PATH and CELERY_APP_REDIS at minimum

# 5. Launch — standard mode, Redis broker, single worker
MODE=standard BROKER_MODE=redis SERVER_PROFILE=medium \
  PROJECT_PROFILE=celery-profile.env \
  ./core/up.sh

# Launch — full mode, hybrid brokers, dual workers with unified Flower
MODE=full BROKER_MODE=hybrid WORKER_MODE=dual SERVER_PROFILE=large \
  PROJECT_PROFILE=celery-profile.env \
  ./core/up.sh
```

> **Important:** Nginx requires TLS certificates to start. Step 3 generates self-signed certs for `localhost` — no domain name needed for local development. See [docs/README.md](docs/README.md) for the full deployment guide including Let's Encrypt setup.

---

## 3. Documentation

- **[docs/README.md](docs/README.md)** — Full deployment and operations reference
- **[docs/DEVELOPER_GUIDE.md](docs/DEVELOPER_GUIDE.md)** — Wiring your Django project to the platform
- **[docs/FAILURE_MODES.md](docs/FAILURE_MODES.md)** — Platform engineering triage (read before going live)
- **[docs/ARCHITECTURE_DIAGRAM.md](docs/ARCHITECTURE_DIAGRAM.md)** — Component topology and port mapping
- **[docs/MTLS-SETUP-GUIDE.md](docs/MTLS-SETUP-GUIDE.md)** — mTLS certificate lifecycle and setup
- **[docs/UPGRADE.md](docs/UPGRADE.md)** — Version upgrade guides and rollback procedures
- **[docs/OS_Commitment.md](docs/OS_Commitment.md)** — Contribution roadmap and status

---

## 4. Directory Structure

```text
django-celery-platform/
├── components/
│   ├── brokers/                        # Redis + RabbitMQ
│   ├── gateway/                        # Nginx, TLS, mTLS, WebSocket proxy
│   ├── workers/
│   │   ├── config/                     # broker_settings, celery_hybrid, path_utils …
│   │   ├── requirements/               # core.txt + capability files
│   │   ├── strategies/
│   │   │   ├── broker.redis.env        # BROKER_MODE selector
│   │   │   ├── broker.rabbitmq.env
│   │   │   ├── broker.hybrid.env
│   │   │   ├── worker.single.env       # WORKER_MODE selector
│   │   │   └── worker.dual.env
│   │   ├── docker-compose.workers.yml  # always loaded
│   │   ├── docker-compose.asgi.yml     # loaded when ASGI_MODE=true
│   │   └── docker-compose.dual-workers.yml  # loaded when WORKER_MODE=dual
│   └── observability/                  # Prometheus, Grafana, Alertmanager
├── core/
│   ├── up.sh                           # Smart Launcher — the only command you need
│   ├── modes/
│   │   ├── minimal.yml
│   │   ├── standard.yml
│   │   ├── full.yml
│   │   └── dual-workers.yml            # scales celery-beat to 0 when WORKER_MODE=dual
│   └── profiles/                       # sizing.small / medium / large .env
├── docs/                               # Platform documentation
├── .docker.env                         # Non-secret system-wide defaults (safe to commit)
├── .env.secrets.example                # Secrets template (safe to commit)
├── .env.secrets                        # Generated secrets — gitignored, never commit
└── init-secrets.sh                     # Zero-trust secrets generator
```
