# Django Celery Platform — Deployment Guide

> **"Deploy once. Choose your stack. Worry no more."**

This is the complete deployment and operations reference for the **Django Celery Platform** — a composable, production-ready infrastructure for running Django + Celery workers with Redis and/or RabbitMQ brokers, full TLS via Nginx, and a complete Prometheus + Grafana observability stack.

---

## 📖 Table of Contents

1. [How It Works](#how-it-works)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Architecture](#architecture)
6. [Configuration Reference](#configuration-reference)
7. [Monitoring & Management](#monitoring--management)
8. [Security](#security)
9. [Troubleshooting](#troubleshooting)
10. [Documentation Index](#documentation-index)

---

## How It Works

Instead of one monolithic deployment, you assemble your stack across five dimensions using the Smart Launcher (`core/up.sh`):

```bash
MODE=standard BROKER_MODE=hybrid SERVER_PROFILE=medium \
  PROJECT_PROFILE=/path/to/my/celery-profile.env \
  ./core/up.sh
```

| Variable | Options | Controls |
|---|---|---|
| `MODE` | `minimal` / `standard` / `full` | Which services boot |
| `BROKER_MODE` | `redis` / `rabbitmq` / `hybrid` | Broker strategy |
| `WORKER_MODE` | `single` / `dual` | Worker topology |
| `SERVER_PROFILE` | `small` / `medium` / `large` | Concurrency + memory limits |
| `CODE_SOURCE` | `bind` / `image` / `git` / `volume` / `pip` | How project code reaches the workers |
| `PROJECT_PROFILE` | path to your `.env` file | Your Django project config |
| `ASGI_MODE` | `true` / `false` | Enables Daphne + Redis Channel Layer for WebSocket |

### Deploy Modes

- `minimal` — Redis broker + fast worker only. No RabbitMQ, no monitoring. Get running in under 5 minutes.
- `standard` — Adds Prometheus + Grafana + all exporters. See problems before users report them.
- `full` — Adds RabbitMQ, Alertmanager (PagerDuty + Slack), and mTLS on Nginx. Production-grade.

### Worker Modes

- `single` — One worker pool matched to `BROKER_MODE`. Default. Works with any broker strategy.
- `dual` — Both `worker-fast` (Redis + gevent) and `worker-critical` (RabbitMQ + solo) run simultaneously with a unified Flower UI at `:5557` monitoring both pools. A single `worker-hybrid-beat` replaces the per-broker Beat. Requires `BROKER_MODE=hybrid`.

### Broker Strategies

- `redis` — Speed-first. Gevent pool, 100 concurrent tasks. Best for notifications, cache invalidation, real-time events.
- `rabbitmq` — Reliability-first. Solo pool, `acks_late`, guaranteed delivery. Best for payments, emails, audit logs.
- `hybrid` — Both. Fast lane (Redis) + secure vault (RabbitMQ) running simultaneously.

> ⚠️ `WORKER_MODE=dual` requires `BROKER_MODE=hybrid`. Both brokers must be running. `up.sh` enforces this at launch time.

> ⚠️ `MODE=minimal` disables RabbitMQ regardless of `BROKER_MODE`. Use `standard` or `full` for RabbitMQ or hybrid strategies.

> ⚠️ `ASGI_MODE=true` adds Daphne + a dedicated Redis Channel Layer. Only enable this if your Django project uses Django Channels. See Step 0 in [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md) for the full ASGI wiring guide.

---

## Prerequisites

### System Requirements

- **OS**: Ubuntu 22.04 or newer (Linux recommended; macOS supported for development)
- **Python**: 3.13+ (worker images ship `python:3.13-slim`)
- **Django**: 4.2 LTS or 5.1+ (worker images ship Django 5.1.7)
- **RAM**: 2GB minimum (`small`), 4GB (`medium`), 8GB+ (`large`)
- **Disk**: 10GB free space
- **Docker**: 24.0+ with Compose plugin v2.2+
- **OpenSSL**: For TLS certificate generation

> **Django version note:** The worker containers install Django 5.1.7 from `requirements/core.txt`
> to load your project settings. If your project runs a different Django version, override it
> by adding `django==<your-version>` to your project's `requirements_celery.txt` — the
> `docker-entrypoint.sh` installs this file automatically on container start.

> **Linux note:** `host.docker.internal` does not resolve on Linux without explicit configuration.
> See the comment in `.docker.env` for the two resolution options.

### Install Docker

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo apt install docker-compose-plugin -y

# IMPORTANT: log out and back in for group membership to take effect
exit
```

Verify:
```bash
docker --version
docker compose version   # must be >= 2.2
```

---

## ⚡ Quick Start

```bash
# 1. Clone the platform
git clone <repo-url> django-celery-platform
cd django-celery-platform

# 2. Generate secrets
./init-secrets.sh
# Edit .env.secrets — fill in SLACK_WEBHOOK_URL, PAGERDUTY_INTEGRATION_KEY, EMAIL_HOST_PASSWORD

# 3. Generate TLS certificates
#    — localhost (no domain required):
./components/gateway/scripts/generate_mtls_certs.sh localhost
#    — custom domain (production):
#    ./components/gateway/scripts/generate_mtls_certs.sh yourdomain.com

# 4. Create your project profile — copy the example and edit it
cp .celery-profile.env.example my-project.env
nano my-project.env   # set APP_PATH, CELERY_APP_REDIS, DJANGO_SETTINGS_MODULE

# 5. Launch
MODE=standard BROKER_MODE=redis SERVER_PROFILE=medium \
  PROJECT_PROFILE=my-project.env \
  ./core/up.sh
```

> **Localhost note:** passing `localhost` to `generate_mtls_certs.sh` produces a self-signed certificate for `127.0.0.1` / `localhost`. Your browser will show a certificate warning — click through it. This is expected for local development. For production, replace with a Let's Encrypt cert (see Step 2 below).

**Check status:**
```bash
./core/up.sh ps
```

**Stop everything:**
```bash
./core/up.sh down
```

---

## 📝 Step-by-Step Deployment

### Step 1 — Secrets

```bash
./init-secrets.sh
```

This generates `.env.secrets` with strong random passwords for Redis, RabbitMQ, Flower, and Grafana. Then edit it to fill in the three placeholders:

```bash
nano .env.secrets
```

```bash
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
PAGERDUTY_INTEGRATION_KEY=your_pagerduty_key
EMAIL_HOST_PASSWORD=your_smtp_password
```

> `.env.secrets` is excluded from version control by `.gitignore`. Never commit it.

---

### Step 2 — TLS Certificates

Nginx requires TLS certificates at `components/gateway/ssl/fullchain.pem` and `privkey.pem`.

**Option A — Self-signed (development / testing):**
```bash
./components/gateway/scripts/generate_mtls_certs.sh yourdomain.com
```

**Option B — Let's Encrypt (production):**
```bash
sudo apt install certbot -y
sudo certbot certonly --standalone -d yourdomain.com

cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem components/gateway/ssl/
cp /etc/letsencrypt/live/yourdomain.com/privkey.pem   components/gateway/ssl/
```

**Option C — Import existing certificates:**
```bash
./components/gateway/scripts/import_mtls_certs.sh /path/to/existing/certs
```

---

### Step 3 — Build Worker Images

```bash
# Base image (all workers)
docker build -t celery-microservice:base \
  -f components/workers/Dockerfile.base \
  components/workers/

# Optional capability images (only build what you need)
docker build -t celery-microservice:mssql \
  -f components/workers/Dockerfile.mssql \
  components/workers/

docker build -t celery-microservice:pdf \
  -f components/workers/Dockerfile.pdf \
  components/workers/
```

All images run as a non-root `celery` user. The base image pins `pip==25.1` for reproducible builds. See `components/workers/Dockerfile.base` for the full build spec.

The `components/workers/config/` package contains the reference Celery configuration modules (`broker_settings.py`, `celery_hybrid.py`, `django_celery_integration.py`). Copy the relevant file into your Django project's `config/` directory and adjust as needed — see `docs/DEVELOPER_GUIDE.md`.

---

### Step 4 — Create Your Project Profile

Create a `celery-profile.env` file in your Django project (or anywhere accessible).
Set `CODE_SOURCE` to match how your Django application is deployed:

```bash
# ── Required: identity ───────────────────────────────────────
PROJECT_NAME=my-app
WORKER_IMAGE=celery-microservice:base

# ── CODE_SOURCE — choose how code reaches the workers ────────
# bind   (default) Django on host (systemd service, bare metal, local dev)
# image            Code baked into WORKER_IMAGE at build time
# volume           Named Docker volume shared with a Django container
# git              Clone APP_GIT_URL at container start
# pip              Install APP_PIP_PACKAGE from PyPI
CODE_SOURCE=bind

# Set the variable that matches your CODE_SOURCE:
APP_PATH=/absolute/path/to/your/django-project   # CODE_SOURCE=bind
# APP_VOLUME_NAME=my_app_code                    # CODE_SOURCE=volume
# APP_GIT_URL=https://github.com/org/repo.git    # CODE_SOURCE=git
# APP_GIT_BRANCH=main                            # CODE_SOURCE=git (optional)
# APP_PIP_PACKAGE=your-project==1.2.3            # CODE_SOURCE=pip

# ── Celery app entrypoints ───────────────────────────────────
CELERY_APP_REDIS=config.celery_redis:app
CELERY_APP_RABBITMQ=config.celery_rabbitmq:app   # only needed for rabbitmq/hybrid

# ── Queue names ──────────────────────────────────────────────
CELERY_REDIS_QUEUE=redis_queue
CELERY_RABBITMQ_QUEUE=critical_queue

# ── Django ───────────────────────────────────────────────────
DJANGO_SETTINGS_MODULE=config.settings.production
DJANGO_ALLOWED_HOSTS=yourdomain.com

# ── Optional: runtime pip injection ─────────────────────────
# EXTRA_PIP_PACKAGES=pysmb==1.2.13 paramiko==3.4.0
```

See `docs/DEVELOPER_GUIDE.md` Step 1.5 for the full `CODE_SOURCE` guide and Step 2 for wiring your Django Celery config to match `BROKER_MODE`.

---

### Step 5 — Configure Firewall

```bash
sudo ufw enable
sudo ufw allow 22/tcp    # SSH — do this first

# Public traffic
sudo ufw allow 80/tcp    # HTTP (redirects to HTTPS)
sudo ufw allow 443/tcp   # HTTPS

# Monitoring — restrict to VPN/office IP in production
sudo ufw allow from YOUR_VPN_IP to any port 8300   # Grafana
sudo ufw allow from YOUR_VPN_IP to any port 9090   # Prometheus
sudo ufw allow from YOUR_VPN_IP to any port 9093   # Alertmanager
sudo ufw allow from YOUR_VPN_IP to any port 5555   # Flower (Redis)
sudo ufw allow from YOUR_VPN_IP to any port 5556   # Flower (RabbitMQ)
sudo ufw allow from YOUR_VPN_IP to any port 15672  # RabbitMQ Management UI

# Internal ports (6379, 5672, 9100–9809) are bound to 127.0.0.1 only
# and are NOT reachable from outside the host — no rules needed.

sudo ufw status
```

---

### Step 6 — Launch

```bash
# Standard mode, Redis-only, medium server
MODE=standard BROKER_MODE=redis SERVER_PROFILE=medium \
  PROJECT_PROFILE=/path/to/celery-profile.env \
  ./core/up.sh

# Full mode, hybrid brokers, dual workers, large server
MODE=full BROKER_MODE=hybrid WORKER_MODE=dual SERVER_PROFILE=large \
  PROJECT_PROFILE=/path/to/celery-profile.env \
  ./core/up.sh

# Full mode, hybrid brokers, single worker (default), large server
MODE=full BROKER_MODE=hybrid WORKER_MODE=single SERVER_PROFILE=large \
  PROJECT_PROFILE=/path/to/celery-profile.env \
  ./core/up.sh
```

---

### Step 7 — Verify

```bash
# Check all containers are healthy
./core/up.sh ps

# Tail all logs
./core/up.sh logs

# Check individual service
docker logs celery-redis-shared
docker logs celery-nginx-shared
```

**Expected running containers (full mode):**

| Container | Component | Port |
|---|---|---|
| `celery-redis-shared` | brokers | 127.0.0.1:6379 |
| `celery-rabbitmq-shared` | brokers | 127.0.0.1:5672, 127.0.0.1:15672 |
| `celery-nginx-shared` | gateway | 0.0.0.0:80, 0.0.0.0:443 |
| `<project>-worker-fast` | workers | — |
| `<project>-worker-critical` | workers | — |
| `<project>-beat` | workers | — (scaled to 0 when `WORKER_MODE=dual`) |
| `<project>-beat-hybrid` | workers | — (only when `WORKER_MODE=dual`) |
| `<project>-flower-redis` | workers | 127.0.0.1:5555 |
| `<project>-flower-rabbitmq` | workers | 127.0.0.1:5556 |
| `<project>-flower-hybrid` | workers | 127.0.0.1:5557 (only when `WORKER_MODE=dual`) |
| `prometheus-shared` | observability | 127.0.0.1:9090 |
| `grafana-shared` | observability | 127.0.0.1:8300 |
| `alertmanager-shared` | observability | 127.0.0.1:9093 |
| `redis-exporter-shared` | observability | 127.0.0.1:9121 |
| `rabbitmq-exporter-shared` | observability | 127.0.0.1:9419 |
| `celery-exporter-redis` | observability | 127.0.0.1:9808 |
| `celery-exporter-rabbitmq` | observability | 127.0.0.1:9809 (host) / 9808 (container) |
| `node-exporter-shared` | observability | 127.0.0.1:9100 |
| `nginx-exporter-shared` | observability | 127.0.0.1:9113 |

---

## 🏗️ Architecture

### Repository Structure

```
django-celery-platform/
├── components/
│   ├── brokers/          # Redis + RabbitMQ — owns celery-broker-net
│   │   ├── docker-compose.brokers.yml
│   │   ├── INTERFACE.md
│   │   ├── CONTRIBUTING.md
│   │   └── tests/smoke_test.sh
│   │
│   ├── gateway/          # Nginx, TLS, mTLS, rate limiting, WebSocket proxy
│   │   ├── docker-compose.gateway.yml
│   │   ├── nginx.conf.template
│   │   ├── ssl/          # Mount fullchain.pem + privkey.pem here
│   │   ├── scripts/
│   │   │   ├── generate_mtls_certs.sh
│   │   │   └── import_mtls_certs.sh
│   │   ├── INTERFACE.md
│   │   ├── CONTRIBUTING.md
│   │   └── tests/smoke_test.sh
│   │
│   ├── workers/          # Celery workers, Beat, Flower, Dockerfiles
│   │   ├── docker-compose.workers.yml
│   │   ├── docker-compose.dual-workers.yml
│   │   ├── docker-entrypoint.sh
│   │   ├── Dockerfile.base / .full / .mssql / .pdf / .smb
│   │   ├── requirements/core.txt + capability files
│   │   ├── config/       # Reference Celery configs for each BROKER_MODE
│   │   ├── strategies/   # broker.*.env / worker.*.env
│   │   ├── INTERFACE.md
│   │   ├── CONTRIBUTING.md
│   │   └── tests/smoke_test.sh
│   │
│   └── observability/    # Prometheus, Grafana, Alertmanager, all exporters
│       ├── docker-compose.monitoring.yml
│       ├── prometheus/   # prometheus.yml, alert_rules.yml, alertmanager.yml
│       ├── grafana/      # Auto-provisioned dashboards (5 JSON files)
│       ├── INTERFACE.md
│       ├── CONTRIBUTING.md
│       └── tests/smoke_test.sh
│
├── core/
│   ├── up.sh             # Smart Launcher — the only command you need
│   ├── modes/            # minimal.yml / standard.yml / full.yml / dual-workers.yml
│   └── profiles/         # sizing.small/medium/large.env
│
├── docs/                 # Global documentation
│   ├── ARCHITECTURE_DIAGRAM.md
│   ├── DEVELOPER_GUIDE.md
│   ├── FAILURE_MODES.md
│   └── OS_Commitment.md
│
├── .docker.env           # Non-secret system-wide defaults
├── .env.secrets          # Generated by init-secrets.sh — never commit
└── init-secrets.sh       # Zero-trust secrets generator
```

### Network Topology

```
External Traffic
      │
      ▼
┌─────────────────────────────────────────────────────┐
│  NGINX  (components/gateway/)                       │
│  :80  → 301 redirect to HTTPS                       │
│  :443 → TLS (TLSv1.2/1.3), WebSocket + HTTP proxy  │
│         /ws/  ──────────────► Django ASGI :9845     │
│         /     ──────────────► Django WSGI :9845     │
│  :8080 → stub_status (internal Docker network only) │
└──────────────────────┬──────────────────────────────┘
                       │  celery-broker-net (10.220.220.0/24)
      ┌────────────────┼────────────────┐
      ▼                ▼                ▼
┌──────────┐   ┌──────────────┐  ┌──────────────────────────────────┐
│  Redis   │   │  RabbitMQ    │  │  Celery Workers                  │
│  :6379   │   │  :5672       │  │  worker-fast                     │
│  broker  │   │  :15672 UI   │  │  worker-critical                 │
│  + result│   │  durable     │  │  celery-beat                     │
│  backend │   │  queues      │  │  flower-redis  :5555             │
└──────────┘   └──────────────┘  │  flower-rmq    :5556             │
                                  │  flower-hybrid :5557 (dual only) │
                                  └──────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────┐
│  Observability  (components/observability/)         │
│  Prometheus  :9090  — scrapes all exporters         │
│  Grafana     :8300  — 5 auto-provisioned dashboards │
│  Alertmanager :9093 — PagerDuty + Slack routing     │
│  Exporters: Redis :9121, RabbitMQ :9419,            │
│             Celery :9808 (×2), Node :9100,          │
│             Nginx :9113                             │
└─────────────────────────────────────────────────────┘
```

### Data Flow

```
HTTP/HTTPS Request:
  Client ──► Nginx :443 (TLS) ──► Django :9845

WebSocket:
  Client ──► Nginx :443 /ws/ ──► Django ASGI :9845

Fast Task Dispatch:
  Django ──► Redis :6379 ──► worker-fast (gevent, 100 concurrent)

Critical Task Dispatch:
  Django ──► RabbitMQ :5672 ──► worker-critical (solo, acks_late)

Dual Worker Monitoring (WORKER_MODE=dual):
  flower-hybrid :5557 ──► worker-fast + worker-critical (unified view)

Metrics Pipeline:
  All services ──► Prometheus :9090 ──► Grafana :8300
                        │
                  Alertmanager :9093 ──► PagerDuty (critical)
                                    └──► Slack    (warning/info)
```

---

## ⚙️ Configuration Reference

### Secrets (`.env.secrets`) — generated by `init-secrets.sh`

| Variable | Description |
|---|---|
| `REDIS_PASSWORD` | Redis broker authentication |
| `RABBITMQ_USER` / `RABBITMQ_PASSWORD` | RabbitMQ credentials |
| `CHANNELS_REDIS_PASSWORD` | Dedicated Redis Channel Layer auth — only required when `ASGI_MODE=true` |
| `FLOWER_USER` / `FLOWER_PASSWORD` | Flower UI basic auth |
| `GF_SECURITY_ADMIN_PASSWORD` | Grafana admin password |
| `SLACK_WEBHOOK_URL` | Alertmanager Slack destination |
| `PAGERDUTY_INTEGRATION_KEY` | Alertmanager PagerDuty destination |
| `EMAIL_HOST_PASSWORD` | SMTP password for Alertmanager email fallback |

### System Defaults (`.docker.env`) — safe to commit

Key overridable defaults:

| Variable | Default | Description |
|---|---|---|
| `DJANGO_UPSTREAM_HOST` | `host.docker.internal` | Django app host for Nginx proxy |
| `DJANGO_UPSTREAM_PORT` | `9845` | Django app port |
| `NGINX_RATE_LIMIT` | `10r/s` | Per-IP rate limit |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `100M` | Max upload size |
| `PROMETHEUS_RETENTION_TIME` | `15d` | Metrics retention |
| `METRICS_TARGET_HOST` | `host.docker.internal` | Django metrics endpoint host |
| `METRICS_TARGET_PORT` | `9845` | Django metrics endpoint port |
| `DJANGO_ALLOWED_HOSTS` | `localhost` | Override with your domain |
| `PROMETHEUS_ENVIRONMENT` | `production` | Label applied to all Prometheus metrics |
| `FLOWER_PORT_HYBRID` | `5557` | Host port for unified Flower UI (`WORKER_MODE=dual` only) |

### Resource Profiles (`core/profiles/`)

| Profile | CPUs | RAM | Fast Concurrency | Critical Concurrency |
|---|---|---|---|---|
| `small` | 1–2 | 2–4GB | 10 | 1 |
| `medium` | 4 | 8GB | 50 | 2* |
| `large` | 8+ | 16GB+ | 150 | 4* |

*Requires `CRITICAL_POOL=prefork` in your project profile to use concurrency > 1.

### TLS / mTLS (`components/gateway/`)

| Port | Mode | Use |
|---|---|---|
| `:80` | HTTP | Redirects to `:443` |
| `:443` | HTTPS TLS 1.2/1.3 | Browser + WebSocket + API traffic |
| `:8080` | HTTP (internal only) | Nginx stub_status for Prometheus scraping |

Certificates must be placed at:
- `components/gateway/ssl/fullchain.pem`
- `components/gateway/ssl/privkey.pem`

---

## 📊 Monitoring & Management

### Access Dashboards

| Service | URL | Credentials |
|---|---|---|
| Application | `https://yourdomain.com` | — |
| Grafana | `http://server:8300` | admin / `GF_SECURITY_ADMIN_PASSWORD` |
| Prometheus | `http://localhost:9090` | — |
| Alertmanager | `http://localhost:9093` | — |
| Flower (Redis) | `http://localhost:5555` | admin / `FLOWER_PASSWORD` |
| Flower (RabbitMQ) | `http://localhost:5556` | admin / `FLOWER_PASSWORD` |
| Flower (Hybrid) | `http://localhost:5557` | admin / `FLOWER_PASSWORD` — only when `WORKER_MODE=dual` |
| RabbitMQ UI | `http://localhost:15672` | admin / `RABBITMQ_PASSWORD` |

### Grafana Dashboards (Auto-Provisioned)

All five dashboards appear on first Grafana startup — no manual import needed.

| Dashboard | Covers |
|---|---|
| Celery Tasks | Workers online, queue depth, failure rate, task runtime p50/p95/p99 |
| Redis | Memory usage, hit rate, evictions, rejected connections |
| RabbitMQ | Queue depth, consumers, publish/deliver rates, unacked messages |
| Node Overview | Host CPU, memory, disk, network I/O |
| Django + Gunicorn | Request rate, latency percentiles, 5xx error rate, top views |

### Smart Launcher Commands

```bash
# Start the stack — dual workers
MODE=full BROKER_MODE=hybrid WORKER_MODE=dual SERVER_PROFILE=large \
  PROJECT_PROFILE=my-project.env ./core/up.sh

# Start the stack — single worker (default)
MODE=full BROKER_MODE=hybrid WORKER_MODE=single SERVER_PROFILE=large \
  PROJECT_PROFILE=my-project.env ./core/up.sh

# Stop the stack
./core/up.sh down

# Restart the stack
MODE=full BROKER_MODE=hybrid WORKER_MODE=dual SERVER_PROFILE=large \
  PROJECT_PROFILE=my-project.env ./core/up.sh restart

# Check container status
./core/up.sh ps

# Tail all logs
./core/up.sh logs
```

---

## 🔐 Security

### Post-Deployment Checklist

- [ ] Run `./init-secrets.sh` — never use placeholder passwords
- [ ] Fill in `SLACK_WEBHOOK_URL`, `PAGERDUTY_INTEGRATION_KEY`, `EMAIL_HOST_PASSWORD` in `.env.secrets`
- [ ] Replace self-signed certs with Let's Encrypt before going live
- [ ] Set `DJANGO_ALLOWED_HOSTS` to your actual domain in `.docker.env`
- [ ] Restrict monitoring ports (8300, 9090, 9093, 5555, 5556, 15672) to VPN/office IP via `ufw`
- [ ] Review alert thresholds in `components/observability/prometheus/alert_rules.yml`
- [ ] Review Alertmanager routing in `components/observability/prometheus/alertmanager.yml`
- [ ] Enable automatic security updates: `sudo apt install unattended-upgrades -y`
- [ ] Set up log rotation for Docker: configure `max-size` / `max-file` in `/etc/docker/daemon.json`
- [ ] Configure volume backups for `redis_data`, `rabbitmq_data`, `beat_data`
- [ ] Do not set `ALLOW_RUNTIME_PIP=true` in production — runtime pip injection is for development only
- [ ] Confirm worker containers are running as the `celery` user: `docker exec <container> whoami`

### Let's Encrypt Certificate Renewal

```bash
# Renew
sudo certbot renew

# Copy renewed certs
cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem components/gateway/ssl/
cp /etc/letsencrypt/live/yourdomain.com/privkey.pem   components/gateway/ssl/

# Reload Nginx (no downtime)
docker exec celery-nginx-shared nginx -s reload
```

---

## 🆘 Troubleshooting

### Container won't start

```bash
docker logs <container_name>
docker inspect <container_name> | grep -A5 '"State"'
```

### Nginx fails to start

Most common cause: missing TLS certificates.
```bash
# Check certs exist
ls -la components/gateway/ssl/

# Regenerate if missing
./components/gateway/scripts/generate_mtls_certs.sh yourdomain.com

# Restart gateway
docker compose -f components/gateway/docker-compose.gateway.yml restart
```

### Workers show offline in Flower

```bash
# Verify worker is actually running
docker logs <project>-worker-fast

# Confirm REDIS_HOST resolves correctly inside the container
docker exec <project>-worker-fast env | grep REDIS_HOST
# Should be: REDIS_HOST=celery-redis-shared
```

See `docs/FAILURE_MODES.md` for the full triage guide covering:
- The Silent Disappearance (Redis eviction)
- The 60-Second Drop (WebSocket timeout)
- The Queue Avalanche (slow worker backlog)
- The OOM Worker Crash (memory leak)

### Port already in use

```bash
sudo ss -tulpn | grep :<PORT>
sudo systemctl stop <conflicting_service>
```

### Containers can't communicate

```bash
docker network ls
docker network inspect celery-broker-net
# All four component containers must appear in this network
```

### Certificate verification error

```bash
# Verify cert chain
openssl verify -CAfile components/gateway/ssl/fullchain.pem \
               components/gateway/ssl/fullchain.pem

# Check cert expiry
openssl x509 -in components/gateway/ssl/fullchain.pem -noout -dates
```

---

## 📚 Documentation Index

| Document | Purpose |
|---|---|
| **[docs/FAILURE_MODES.md](FAILURE_MODES.md)** | Platform engineering triage — read before going live |
| **[docs/DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)** | How to wire your Django Celery config to each `BROKER_MODE` |
| **[docs/ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)** | Full service topology and port mapping |
| **[docs/OS_Commitment.md](OS_Commitment.md)** | Open source contribution roadmap |
| **[docs/MTLS-SETUP-GUIDE.md](MTLS-SETUP-GUIDE.md)** | mTLS certificate lifecycle |
| **[docs/UPGRADE.md](UPGRADE.md)** | Version upgrade guides and rollback procedures |
| **[components/brokers/CONTRIBUTING.md](../components/brokers/CONTRIBUTING.md)** | Contribute to Redis/RabbitMQ topology |
| **[components/gateway/CONTRIBUTING.md](../components/gateway/CONTRIBUTING.md)** | Contribute to Nginx/mTLS/rate limiting |
| **[components/workers/CONTRIBUTING.md](../components/workers/CONTRIBUTING.md)** | Contribute to Celery workers/Dockerfiles |
| **[components/observability/CONTRIBUTING.md](../components/observability/CONTRIBUTING.md)** | Contribute to Prometheus/Grafana/Alertmanager |

---

## 🎯 Success Criteria

Your deployment is successful when:

- [ ] `./core/up.sh ps` shows all expected containers as healthy
- [ ] `https://yourdomain.com` loads your Django application
- [ ] Grafana at `http://server:8300` shows all 5 dashboards with live data
- [ ] Prometheus at `http://localhost:9090/targets` shows all scrape targets as UP
- [ ] Flower at `http://localhost:5555` shows workers online
- [ ] A test task dispatched from Django appears in Flower and completes
- [ ] *(WORKER_MODE=dual only)* Flower Hybrid at `http://localhost:5557` shows both `fast@` and `critical@` workers online
- [ ] No errors in `./core/up.sh logs`
- [ ] TLS certificate is valid (not self-signed) for production
- [ ] All passwords in `.env.secrets` are non-placeholder values
- [ ] Firewall restricts monitoring ports to VPN/office IP
- [ ] *(ASGI_MODE=true only)* WebSocket upgrades successfully: `wscat -c wss://yourdomain.com/ws/ --no-check` returns HTTP 101

---

**Version**: 3.1.0
**Project**: django-celery-platform
**Architecture**: Composable Monorepo Component Model
**Last Updated**: 2026-04
**Maintained By**: Your Team — see [OS_Commitment.md](OS_Commitment.md) for contribution roadmap
