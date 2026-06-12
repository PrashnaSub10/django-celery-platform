# Contribution Roadmap — Where Help Is Needed and Who It Serves

django-celery-platform exists because every Django team rebuilds the same
infrastructure: a broker, workers, a gateway, monitoring, TLS, secrets — and
every team makes the same mistakes doing it. The platform encodes those
lessons once, behind six composable dimensions, so a solo developer or a
five-person startup deploys in minutes what normally takes weeks of DevOps
work. Contributing here multiplies that leverage: one merged provider or fix
lands in every consuming project.

---

## 1. What each module solves — and for which industries

The platform's modules map to workload patterns, and workload patterns map to
industries. This is the honest coverage matrix:

### Broker lanes (`BROKER_MODE`)

| Lane | Broker + worker | Workload guarantee | Industries served |
|---|---|---|---|
| Fast | Redis + gevent (`worker-fast`) | High-throughput, loss-tolerant | SaaS (cache invalidation, notifications), e-commerce (session events), media (thumbnailing), marketing tech |
| Critical | RabbitMQ + prefork (`worker-critical`), acks_late, DLQ helper | Durable, acknowledged, replayable | **Fintech, insurance, banking, government** (payments, OTP/email, audit trails, compliance docs), healthcare (orders, results delivery) |
| Streaming | Kafka + prefork (`worker-kafka`) | Ordered, high-volume, replayable log | IoT/telemetry, logistics tracking, ad-tech event ingestion, analytics pipelines, log aggregation |

### Other dimensions

| Module | Solves | Industry pull |
|---|---|---|
| Gateway (Nginx, TLS 1.2/1.3, mTLS, rate limiting, WS proxy) | Edge security without a dedicated infra engineer | mTLS + rate limiting = regulated APIs (fintech, gov B2B integrations); WS proxy = real-time dashboards, trading UIs, chat |
| Observability (Prometheus + Grafana, 5 dashboards, Alertmanager → PagerDuty/Slack) | Day-2 operations out of the box | Anyone with an SLA; mandatory evidence trail for regulated/audited industries |
| `CODE_SOURCE` (bind/image/volume/git/pip) | Code delivery decoupled from deployment topology | bind = solo dev; image = CI/CD orgs and multi-node scaling; git = agencies managing many client deployments |
| `SERVER_PROFILE` + `MODE` | Right-sizing from 2GB VPS to 16GB server | Startups grow through profiles instead of re-architecting |
| Worker image variants (base/mssql/pdf/smb/full) | Native-dependency classes pre-baked | mssql = enterprises on SQL Server (insurance, banking, gov — proven by this platform's own origin); pdf = document-heavy industries (insurance policies, invoices, reports); smb = orgs with Windows file-share legacy |
| `ASGI_MODE` (Daphne + Channels) | WebSocket + HTTP split behind one gateway | Live dashboards, operations centers, collaborative tools |

**Coverage ceiling (be honest with adopters):** Docker Compose carries Stages
1–3 of the scaling model (~single host to externalized brokers, ~1M req/day).
Kubernetes-scale orgs need the Helm chart (scaffolded, not finished).
Multi-tenant hosting (agencies, platform teams) is designed (Hub-and-Spoke)
but not implemented.

---

## 2. Contribution menu — by effort and impact

### Good first issues (hours, high leverage)

| Item | What it unlocks |
|---|---|
| `WORKER_REPLICAS` variable (`--scale` flags in `up.sh`) | First horizontal-scaling step for growing startups |
| `GATEWAY_MODE=external` (docs + 4-line up.sh change) | Teams behind ALB/CloudFront/CDN — large slice of cloud adopters |
| `OBSERVABILITY_MODE=none` toggle | Teams with existing Datadog/New Relic stop running a parallel stack |
| Smoke-test hardening (`.github/workflows/smoke.yml` just landed — iterate on it) | Trustworthy PRs for everyone |
| Docs: per-industry quick-start recipes (fintech profile, IoT profile) | Faster evaluation for the exact audiences in §1 |

### Contributor tier (days)

| Item | What it unlocks |
|---|---|
| `GATEWAY_MODE=caddy` / `traefik` providers (directory convention — no up.sh edits, see Additional_Works.md) | Auto-TLS (caddy) for solo devs; dynamic ingress (traefik) for multi-project hosts |
| `OBSERVABILITY_MODE=datadog` / `cloudwatch` providers | Enterprise monitoring-stack compatibility |
| `REDIS_MODE=external` / `RABBITMQ_MODE=external` / `KAFKA_MODE=external` | Stage 3: managed brokers (ElastiCache, AmazonMQ, MSK) with zero task-code changes |
| Secrets seams (document Vault/ASM injection points — do NOT hack `.env.secrets` mounting) | Teams with real secret managers |
| Per-queue Grafana template variables | Multi-project observability (Hub-and-Spoke prerequisite) |

### Maintainer tier (weeks)

| Item | What it unlocks |
|---|---|
| Finish Helm chart (`runtime/kubernetes/helm/`) + KEDA queue-depth autoscaling | Kubernetes orgs; Stages 4–5 of the scaling model |
| Hub-and-Spoke multi-tenancy (design record exists — Redis DB/vhost isolation, conf.d gateway routing) | Agencies and platform teams hosting many Django projects on shared brokers |
| `SCALE_PROFILE` presets (solo/startup/scale/enterprise) | One-variable tier selection |

### Operational debt (from real deployment cycles — see CHANGELOG [Unreleased])

- Watch the first GHCR publish run; fix and tag so consumers pull instead of build.
- Cut a tagged release once smoke CI is green — adopters need something to pin.
- Profile-drift warning in `up.sh` (bind-mounted profile differing from its committed copy reverted a deployment mid-cycle).
- Document the two-dotenv pattern for consumers (host-lane vs container-lane URLs — the `CELERY_BROKER_URL` env-override trap cost a real deployment hours).

---

## 3. Contribution rules of the road

1. **Directory convention over conditionals.** New gateway/observability
   providers are new subdirectories; `up.sh` must never grow `if` branches
   per provider.
2. **Every provider ships `tests/smoke_test.sh`** following the existing
   `components/*/tests/` pattern.
3. **Additive and backward-compatible.** Existing deployments that set none
   of your new variables must behave identically.
4. **Name limitations honestly.** The platform's credibility with regulated
   industries rests on documented gaps, not marketing.
5. Use the `demo/` stack for development — no TLS/secrets setup needed.

---

**Version**: 3.1.0
**Project**: django-celery-platform
**Architecture**: Composable Monorepo Component Model
**Last Updated**: 2026-06
**License**: MIT — see LICENSE in the repository root
