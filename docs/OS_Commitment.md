# Open Source Commitment & Contribution Architecture

This document describes the contribution model for `django-celery-platform` and
tracks the status of each commitment against the actual repository state.

---

## 1. The Component Isolation Strategy

The repository follows a **Composable Monorepo Component Model**. Each domain is
an isolated project with its own bounded context, documentation, interface
contract, and test suite.

### Current Repository Structure

```text
django-celery-platform/
├── components/
│   ├── gateway/               # Nginx, mTLS, rate limiting, WebSocket proxy
│   │   ├── nginx.conf.template
│   │   ├── docker-compose.gateway.yml
│   │   ├── scripts/           # generate_mtls_certs.sh, import_mtls_certs.sh
│   │   ├── ssl/               # Mount fullchain.pem + privkey.pem here
│   │   ├── INTERFACE.md       # Port contracts, env var inputs/outputs
│   │   ├── CONTRIBUTING.md    # How to test Nginx configs in isolation
│   │   └── tests/smoke_test.sh
│   │
│   ├── workers/               # Celery workers, Dockerfiles, config package
│   │   ├── config/            # broker_settings, celery_hybrid, path_utils …
│   │   ├── requirements/      # core.txt + capability files (mssql, pdf, smb)
│   │   ├── strategies/        # broker.redis/rabbitmq/hybrid.env
│   │   ├── docker-compose.workers.yml
│   │   ├── docker-compose.asgi.yml
│   │   ├── docker-entrypoint.sh
│   │   ├── Dockerfile.base / .mssql / .pdf / .smb / .full
│   │   ├── INTERFACE.md
│   │   ├── CONTRIBUTING.md
│   │   └── tests/smoke_test.sh
│   │
│   ├── brokers/               # Redis + RabbitMQ topologies
│   │   ├── docker-compose.brokers.yml
│   │   ├── INTERFACE.md
│   │   ├── CONTRIBUTING.md
│   │   └── tests/smoke_test.sh
│   │
│   └── observability/         # Prometheus, Grafana, Alertmanager, exporters
│       ├── prometheus/        # prometheus.yml.template, alert_rules, alertmanager
│       ├── grafana/           # Auto-provisioned dashboards (5 JSON files)
│       ├── docker-compose.monitoring.yml
│       ├── INTERFACE.md
│       ├── CONTRIBUTING.md
│       └── tests/smoke_test.sh
│
├── core/                      # Orchestration brain
│   ├── up.sh                  # Smart Launcher — the only command you need
│   ├── modes/                 # minimal.yml / standard.yml / full.yml
│   └── profiles/              # sizing.small / medium / large .env
│
├── docs/                      # Platform-wide documentation
│   ├── README.md              # Deployment guide
│   ├── DEVELOPER_GUIDE.md     # Django wiring guide
│   ├── ARCHITECTURE_DIAGRAM.md
│   ├── FAILURE_MODES.md
│   ├── MTLS-SETUP-GUIDE.md
│   └── OS_Commitment.md       # This file
│
└── .github/                   # CI/CD — see Gap 1 below
    ├── workflows/
    │   ├── test-gateway.yml
    │   ├── test-workers.yml
    │   ├── test-brokers.yml
    │   └── test-observability.yml
    └── CODEOWNERS
```

---

## 2. Why This Model Works for Open Source

### Lower Barrier to Entry

Each component boots and tests in complete isolation. A Grafana contributor
never needs to understand Celery. An Nginx specialist never needs Python.
The `INTERFACE.md` in each component defines the exact contract — ports,
env vars, network expectations — so contributors know exactly what they
can and cannot touch.

### Isolated CI/CD Pipelines

When a contributor modifies `components/gateway/nginx.conf.template`,
only `test-gateway.yml` runs. No Python workers spin up, no Celery
integration tests execute. Fast feedback, minimal CI cost.

### Dedicated Maintainership via CODEOWNERS

```text
# .github/CODEOWNERS
/components/gateway/       @security-team @nginx-experts
/components/observability/ @data-engineers
/components/workers/       @python-backend-devs
/components/brokers/       @infrastructure-team
/core/                     @platform-architects
/docs/                     @platform-architects
```

---

## 3. Contribution Workflows per Module

### Worker Module (`components/workers/`)

Contributors: Python developers, Django ecosystem experts.

Goals:
- Optimising `Dockerfile.base` layer size
- Adding new capability images (e.g. `Dockerfile.gpu` for AI/ML tasks)
- Extending `config/broker_settings.py` with new conf presets
- Improving `docker-entrypoint.sh` dependency injection

Testing:
```bash
cd components/workers
bash tests/smoke_test.sh
```

### Gateway Module (`components/gateway/`)

Contributors: DevSecOps, Nginx specialists, networking engineers.

Goals:
- Improving HTTP/3 (QUIC) support
- Adding WAF rule sets
- Enhancing mTLS certificate rotation automation

Testing:
```bash
cd components/gateway
bash tests/smoke_test.sh
```

WebSocket smoke test after any gateway change:
```bash
# npm install -g wscat
wscat -c wss://localhost/ws/test/ --no-check
# Expected: HTTP 101 Switching Protocols
```

### Observability Module (`components/observability/`)

Contributors: SREs, Prometheus/Grafana experts.

Goals:
- Adding cross-referenced Grafana dashboards
- Writing more precise Alertmanager routing templates
- Adding new scrape targets for additional exporters

Testing:
```bash
cd components/observability
bash tests/smoke_test.sh
```

### Brokers Module (`components/brokers/`)

Contributors: Infrastructure engineers, Redis/RabbitMQ specialists.

Goals:
- Adding Redis Sentinel or Cluster topology
- RabbitMQ federation / shovel configuration
- Split-brain and network partition test scenarios

Testing:
```bash
cd components/brokers
bash tests/smoke_test.sh
```

---

## 4. Commitment Status

| Commitment | Status |
|---|---|
| Monorepo component model | Done |
| Component isolation (independent boot + test) | Done |
| Per-component `INTERFACE.md` | Done |
| Per-component `CONTRIBUTING.md` | Done |
| Per-component `tests/smoke_test.sh` | Done |
| Python config package (`broker_settings`, `celery_hybrid`, `path_utils`) | Done |
| Security hardening (CWE-22, CWE-88, shell injection, GPG pipe) | Done |
| Strict linting, type annotations, `__all__`, immutable shared state | Done |
| PII removed from all committed files | Done |
| `legacy/` excluded from repository via `.gitignore` | Done |
| `.github/workflows/` — per-component CI pipelines | **Pending** |
| `.github/CODEOWNERS` — ownership enforcement on PRs | **Pending** |

The two pending items are the only remaining blockers for a public release.
The smoke tests that the CI workflows would run already exist and pass.
