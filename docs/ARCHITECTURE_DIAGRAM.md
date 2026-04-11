# 🏗️ Architecture & Component Topology

The `django-celery-platform` is a **composable, production-ready Docker infrastructure platform** for running Django + Celery workers. Your Django project lives on the host (or in a container); this platform provides the broker, worker, gateway, and observability layers via Docker Compose.

**Core principle:** Deploy once. Choose your stack. Worry no more.

---

## 1. How It Works — The Big Picture

```mermaid
graph TB
    subgraph "YOUR DJANGO PROJECT"
        DJ["Django Application<br/>(on host or in container)"]
        Tasks["tasks.py<br/>@shared_task decorators"]
    end

    subgraph "DJANGO CELERY PLATFORM"
        direction TB

        subgraph "🧠 Core Orchestrator"
            UP["core/up.sh<br/>Smart Launcher"]
        end

        subgraph "🌐 Gateway Layer"
            NGX["Nginx<br/>TLS / mTLS / Rate Limiting"]
        end

        subgraph "📨 Broker Layer"
            REDIS["Redis<br/>Fast broker + Result backend"]
            RMQ["RabbitMQ<br/>Durable broker"]
            KAFKA["Kafka<br/>Streaming broker"]
        end

        subgraph "⚙️ Worker Layer"
            WF["worker-fast<br/>gevent · Redis queue"]
            WC["worker-critical<br/>solo · RabbitMQ queue"]
            WK["worker-kafka<br/>prefork · Kafka topics"]
            BEAT["Celery Beat<br/>Periodic scheduler"]
            FL["Flower UIs<br/>:5555 :5556 :5557 :5558"]
        end

        subgraph "📊 Observability Layer"
            PROM["Prometheus"]
            GRAF["Grafana<br/>5 dashboards"]
            ALERT["Alertmanager"]
            EXP["Metric Exporters<br/>Redis · RabbitMQ · Celery<br/>Node · Nginx"]
        end
    end

    DJ -->|"dispatches tasks"| REDIS
    DJ -->|"dispatches tasks"| RMQ
    DJ -->|"dispatches tasks"| KAFKA
    Tasks -.->|"code delivered via<br/>CODE_SOURCE"| WF
    Tasks -.->|"code delivered via<br/>CODE_SOURCE"| WC

    WF <-->|"consume/ack"| REDIS
    WC <-->|"consume/ack"| RMQ
    WK <-->|"consume/commit"| KAFKA
    WF -->|"store results"| REDIS
    WC -->|"store results"| REDIS
    WK -->|"store results"| REDIS
    BEAT -->|"schedule"| REDIS
    BEAT -->|"schedule"| RMQ

    NGX -->|"proxy :9845"| DJ
    PROM -->|"scrape"| EXP
    EXP -->|"query"| REDIS
    EXP -->|"query"| RMQ
    EXP -->|"query"| NGX
    GRAF -->|"visualise"| PROM
    ALERT -->|"notify"| PROM

    UP -->|"orchestrates"| NGX
    UP -->|"orchestrates"| REDIS
    UP -->|"orchestrates"| WF

    style DJ fill:#4f46e5,color:#fff,stroke:#4338ca
    style UP fill:#f59e0b,color:#000,stroke:#d97706
    style REDIS fill:#dc2626,color:#fff,stroke:#b91c1c
    style RMQ fill:#16a34a,color:#fff,stroke:#15803d
    style KAFKA fill:#0ea5e9,color:#fff,stroke:#0284c7
    style NGX fill:#6366f1,color:#fff,stroke:#4f46e5
    style PROM fill:#ea580c,color:#fff,stroke:#c2410c
    style GRAF fill:#7c3aed,color:#fff,stroke:#6d28d9
```

---

## 2. Six Configuration Dimensions

The platform is controlled by **six independent dimensions**, set as environment variables. Every combination produces a valid, tested stack.

```mermaid
mindmap
  root(("up.sh<br/>Smart Launcher"))
    MODE
      minimal
        Redis only
        No monitoring
        Solo developer
      standard
        Redis + Monitoring
        No RabbitMQ
        Small teams
      full
        All brokers
        Full observability
        Alerting + mTLS
    BROKER_MODE
      redis
        Fast ephemeral tasks
      rabbitmq
        Durable critical tasks
      hybrid
        Redis + RabbitMQ
      kafka
        Streaming pipelines
    WORKER_MODE
      single
        One worker type
      dual
        fast + critical pools
        Requires hybrid broker
    SERVER_PROFILE
      small
        Low resources
      medium
        Balanced
      large
        High throughput
    CODE_SOURCE
      bind
        Host filesystem mount
      image
        Baked into Docker image
      volume
        Named Docker volume
      git
        Clone at startup
      pip
        Install from PyPI
    RESULT_BACKEND
      redis
        Redis DB 1
      django-db
        Django ORM
      postgres
        Direct PostgreSQL
      none
        Disabled
```

### Dimension Quick Reference

| Dimension | Variable | Options | Default | Controls |
|---|---|---|---|---|
| Deploy Mode | `MODE` | `minimal` · `standard` · `full` | `standard` | Which services boot |
| Broker Strategy | `BROKER_MODE` | `redis` · `rabbitmq` · `hybrid` · `kafka` | `redis` | Message routing |
| Worker Topology | `WORKER_MODE` | `single` · `dual` | `single` | Worker pool layout |
| Server Sizing | `SERVER_PROFILE` | `small` · `medium` · `large` | `medium` | Concurrency + memory |
| Code Delivery | `CODE_SOURCE` | `bind` · `image` · `volume` · `git` · `pip` | `bind` | How code reaches workers |
| Result Storage | `RESULT_BACKEND` | `redis` · `django-db` · `postgres` · `none` | `redis` | Task result persistence |

### Constraint Rules

```mermaid
graph LR
    DUAL["WORKER_MODE=dual"] -->|"requires"| HYBRID["BROKER_MODE=hybrid"]
    KAFKA_B["BROKER_MODE=kafka"] -->|"requires"| SINGLE["WORKER_MODE=single"]
    KAFKA_B -->|"incompatible"| DUAL
    DUAL -->|"incompatible"| KAFKA_B

    style DUAL fill:#f59e0b,color:#000
    style HYBRID fill:#16a34a,color:#fff
    style KAFKA_B fill:#0ea5e9,color:#fff
    style SINGLE fill:#64748b,color:#fff
```

---

## 3. Three Broker Lanes

Each broker serves a **distinct workload pattern**. They are not interchangeable.

```mermaid
graph LR
    subgraph "⚡ Fast Lane"
        direction TB
        R_B["Redis Broker"]
        R_W["worker-fast<br/>gevent · 100 concurrency"]
        R_FL["flower-redis :5555"]
        R_B --> R_W
        R_W --> R_FL
    end

    subgraph "🔒 Critical Lane"
        direction TB
        Q_B["RabbitMQ Broker"]
        Q_W["worker-critical<br/>solo · 1 concurrency"]
        Q_FL["flower-rabbitmq :5556"]
        Q_B --> Q_W
        Q_W --> Q_FL
    end

    subgraph "🌊 Streaming Lane"
        direction TB
        K_B["Kafka Broker<br/>KRaft · 3 partitions"]
        K_W["worker-kafka<br/>prefork · 4 concurrency"]
        K_FL["flower-kafka :5558"]
        K_B --> K_W
        K_W --> K_FL
    end

    R_B -.->|"result backend<br/>for all lanes"| RES["Redis DB 1<br/>(Result Storage)"]
    Q_B -.-> RES
    K_B -.-> RES

    style R_B fill:#dc2626,color:#fff
    style Q_B fill:#16a34a,color:#fff
    style K_B fill:#0ea5e9,color:#fff
    style RES fill:#f97316,color:#fff
```

| Lane | Broker | Worker | Pool | Use Case |
|---|---|---|---|---|
| **Fast** | Redis | `worker-fast` | gevent | Notifications, cache warming, API calls, real-time push |
| **Critical** | RabbitMQ | `worker-critical` | solo | Payments, financial transactions, report generation |
| **Streaming** | Kafka | `worker-kafka` | prefork | Event ingestion, log aggregation, data pipelines |

---

## 4. Deploy Modes — What Boots When

```mermaid
graph TD
    subgraph "MODE=minimal"
        direction TB
        M_R["✅ Redis"]
        M_N["✅ Nginx"]
        M_WF["✅ worker-fast"]
        M_BT["✅ Beat"]
        M_FR["✅ Flower Redis :5555"]
        M_RQ["❌ RabbitMQ"]
        M_KA["❌ Kafka"]
        M_OB["❌ Observability"]
    end

    subgraph "MODE=standard"
        direction TB
        S_R["✅ Redis"]
        S_N["✅ Nginx"]
        S_WF["✅ worker-fast"]
        S_BT["✅ Beat"]
        S_FR["✅ Flower Redis :5555"]
        S_PR["✅ Prometheus"]
        S_GR["✅ Grafana"]
        S_EX["✅ Exporters"]
        S_RQ["❌ RabbitMQ"]
        S_KA["❌ Kafka"]
        S_AL["❌ Alertmanager"]
    end

    subgraph "MODE=full"
        direction TB
        F_R["✅ Redis"]
        F_RQ["✅ RabbitMQ"]
        F_KA["✅ Kafka"]
        F_N["✅ Nginx + mTLS"]
        F_WF["✅ worker-fast"]
        F_WC["✅ worker-critical"]
        F_BT["✅ Beat"]
        F_FR["✅ All Flower UIs"]
        F_PR["✅ Full Observability"]
        F_AL["✅ Alertmanager"]
    end

    style M_R fill:#16a34a,color:#fff
    style M_RQ fill:#991b1b,color:#fff
    style S_R fill:#16a34a,color:#fff
    style S_PR fill:#16a34a,color:#fff
    style S_RQ fill:#991b1b,color:#fff
    style F_R fill:#16a34a,color:#fff
    style F_RQ fill:#16a34a,color:#fff
    style F_KA fill:#16a34a,color:#fff
```

---

## 5. `up.sh` — The Smart Launcher Flow

`core/up.sh` is the **only entry point**. It validates dimensions, loads compose fragments, and launches the stack.

```mermaid
flowchart TD
    START(["./core/up.sh"]) --> CHK_SEC{"🔐 .env.secrets<br/>exists?"}
    CHK_SEC -->|No| ERR1["❌ Run init-secrets.sh"]
    CHK_SEC -->|Yes| LOAD_PROF["Load PROJECT_PROFILE<br/>(celery-profile.env)"]

    LOAD_PROF --> VAL["Validate all 6 dimensions<br/>against allowlists"]
    VAL -->|Invalid| ERR2["❌ Dimension value error"]
    VAL -->|Valid| CHK_CS{"CODE_SOURCE<br/>mode?"}

    CHK_CS -->|bind| CHK_APP{"APP_PATH set?"}
    CHK_CS -->|git| CHK_GIT{"APP_GIT_URL set?"}
    CHK_CS -->|volume| CHK_VOL{"APP_VOLUME_NAME set?"}
    CHK_CS -->|pip| CHK_PIP{"APP_PIP_PACKAGE set?"}
    CHK_CS -->|image| OK_CS["✅ No extra var needed"]

    CHK_APP -->|Yes| OK_CS
    CHK_GIT -->|Yes| OK_CS
    CHK_VOL -->|Yes| OK_CS
    CHK_PIP -->|Yes| OK_CS
    CHK_APP -->|No| ERR3["❌ Missing required var"]
    CHK_GIT -->|No| ERR3
    CHK_VOL -->|No| ERR3
    CHK_PIP -->|No| ERR3

    OK_CS --> CHK_COMPAT{"Compatibility<br/>checks"}
    CHK_COMPAT -->|"dual + !hybrid"| ERR4["❌ dual requires hybrid"]
    CHK_COMPAT -->|"kafka + dual"| ERR5["❌ kafka + dual incompatible"]
    CHK_COMPAT -->|OK| BUILD["Build compose command"]

    BUILD --> LAYER["Layer compose fragments:<br/>1. brokers.yml<br/>2. gateway.yml<br/>3. workers.yml<br/>4. code-source overlay<br/>5. asgi.yml (if ASGI_MODE)<br/>6. dual-workers.yml (if dual)<br/>7. kafka-workers.yml (if kafka)<br/>8. monitoring.yml<br/>9. mode override<br/>10. env files + secrets"]

    LAYER --> CMD{{"docker compose up -d"}}
    CMD --> DONE(["✅ Stack is up"])

    style START fill:#f59e0b,color:#000
    style DONE fill:#16a34a,color:#fff
    style ERR1 fill:#dc2626,color:#fff
    style ERR2 fill:#dc2626,color:#fff
    style ERR3 fill:#dc2626,color:#fff
    style ERR4 fill:#dc2626,color:#fff
    style ERR5 fill:#dc2626,color:#fff
```

---

## 6. Compose File Layering

`up.sh` assembles a Docker Compose command from multiple fragments. This diagram shows **which fragments are loaded and when**.

```mermaid
graph TD
    subgraph "Always Loaded"
        B["brokers/<br/>docker-compose.brokers.yml"]
        G["gateway/<br/>docker-compose.gateway.yml"]
        W["workers/<br/>docker-compose.workers.yml"]
        M["observability/<br/>docker-compose.monitoring.yml"]
        MODE_F["modes/{MODE}.yml"]
        ENV1[".docker.env"]
        ENV2["PROJECT_PROFILE"]
        ENV3["sizing.{SERVER_PROFILE}.env"]
        ENV4["broker.{BROKER_MODE}.env"]
        ENV5["worker.{WORKER_MODE}.env"]
        ENV6[".env.secrets"]
    end

    subgraph "Conditional — CODE_SOURCE"
        CS_B["workers.code-bind.yml"]
        CS_V["workers.code-volume.yml"]
        CS_G["workers.code-git.yml"]
    end

    subgraph "Conditional — WORKER_MODE=dual"
        DW["dual-workers.yml"]
        DW_M["modes/dual-workers.yml"]
        DW_CS["dual-workers.code-*.yml"]
    end

    subgraph "Conditional — ASGI_MODE=true"
        ASGI["asgi.yml"]
        ASGI_CS["asgi.code-*.yml"]
    end

    subgraph "Conditional — BROKER_MODE=kafka"
        KW["kafka-workers.yml"]
        KW_M["modes/kafka-broker.yml"]
        KW_CS["kafka-workers.code-*.yml"]
    end

    W --> CS_B
    W --> CS_V
    W --> CS_G
    W --> DW
    DW --> DW_CS
    W --> ASGI
    ASGI --> ASGI_CS
    W --> KW
    KW --> KW_CS

    style B fill:#dc2626,color:#fff
    style G fill:#6366f1,color:#fff
    style W fill:#f59e0b,color:#000
    style M fill:#7c3aed,color:#fff
    style MODE_F fill:#64748b,color:#fff
```

---

## 7. Network Topology & Port Map

All containers share the `celery-broker-net` Docker network (`10.220.220.0/24`).

```mermaid
graph LR
    subgraph "celery-broker-net (10.220.220.0/24)"
        direction TB

        subgraph "Externally Accessible"
            N80["Nginx :8080 → :80 HTTP"]
            N443["Nginx :8443 → :443 HTTPS"]
            F1["Flower Redis :5555"]
            F2["Flower RabbitMQ :5556"]
            F3["Flower Hybrid :5557"]
            F4["Flower Kafka :5558"]
            GR["Grafana :8300"]
            PR["Prometheus :9090"]
            AL["Alertmanager :9093"]
            RM["RabbitMQ Mgmt :15672"]
        end

        subgraph "Internal Only (127.0.0.1)"
            RE["Redis :6379"]
            RQ["RabbitMQ :5672"]
            KA["Kafka :9092"]
            E1["redis-exporter :9121"]
            E2["rabbitmq-exporter :9419"]
            E3["celery-exporter-redis :9808"]
            E4["celery-exporter-rmq :9809"]
            E5["node-exporter :9100"]
            E6["nginx-exporter :9113"]
        end
    end

    HOST["Docker Host"] --> N80
    HOST --> N443
    HOST --> F1
    HOST --> GR
    HOST --> PR

    style HOST fill:#1e293b,color:#fff
```

### Full Port Reference

| Port | Variable | Service | Binding | Overridable |
|---|---|---|---|---|
| `:8080` | `NGINX_HTTP_PORT` | Nginx HTTP | external | ✅ |
| `:8443` | `NGINX_HTTPS_PORT` | Nginx HTTPS | external | ✅ |
| `:5555` | `FLOWER_PORT_REDIS` | Flower Redis | `127.0.0.1` | ✅ |
| `:5556` | `FLOWER_PORT_RABBITMQ` | Flower RabbitMQ | `127.0.0.1` | ✅ |
| `:5557` | `FLOWER_PORT_HYBRID` | Flower Hybrid | `127.0.0.1` | ✅ |
| `:5558` | `FLOWER_PORT_KAFKA` | Flower Kafka | `127.0.0.1` | ✅ |
| `:8300` | `PORT_GRAFANA` | Grafana | `127.0.0.1` | ✅ |
| `:9090` | `PORT_PROMETHEUS` | Prometheus | `127.0.0.1` | ✅ |
| `:9093` | `PORT_ALERTMANAGER` | Alertmanager | `127.0.0.1` | ✅ |
| `:15672` | `PORT_RABBITMQ_MGMT` | RabbitMQ Management | `127.0.0.1` | ✅ |
| `:6379` | `PORT_REDIS` | Redis | `127.0.0.1` | ✅ |
| `:5672` | `PORT_RABBITMQ` | RabbitMQ AMQP | `127.0.0.1` | ✅ |
| `:9092` | `PORT_KAFKA` | Kafka | `127.0.0.1` | ✅ |
| `:9121` | `PORT_REDIS_EXPORTER` | Redis Exporter | `127.0.0.1` | ✅ |
| `:9419` | `PORT_RABBITMQ_EXPORTER` | RabbitMQ Exporter | `127.0.0.1` | ✅ |
| `:9808` | `PORT_CELERY_EXPORTER_REDIS` | Celery Exporter (Redis) | `127.0.0.1` | ✅ |
| `:9809` | `PORT_CELERY_EXPORTER_RABBITMQ` | Celery Exporter (RabbitMQ) | `127.0.0.1` | ✅ |
| `:9100` | `PORT_NODE_EXPORTER` | Node Exporter | `127.0.0.1` | ✅ |
| `:9113` | `PORT_NGINX_EXPORTER` | Nginx Exporter | `127.0.0.1` | ✅ |

---

## 8. CODE_SOURCE — How Code Reaches Workers

Workers need your Django project code to execute tasks. `CODE_SOURCE` controls how that code arrives.

```mermaid
flowchart LR
    subgraph "Your Django Project"
        CODE["tasks.py<br/>models.py<br/>views.py<br/>..."]
    end

    CODE -->|"CODE_SOURCE=bind"| BIND["Bind Mount<br/>Host → /app"]
    CODE -->|"CODE_SOURCE=image"| IMAGE["COPY in Dockerfile<br/>Baked into image"]
    CODE -->|"CODE_SOURCE=volume"| VOLUME["Named Docker Volume<br/>Shared with Django container"]
    CODE -->|"CODE_SOURCE=git"| GIT["git clone at startup<br/>git pull on restart"]
    CODE -->|"CODE_SOURCE=pip"| PIP["pip install at startup<br/>Into site-packages"]

    BIND --> WORKER["Worker Container<br/>/app"]
    IMAGE --> WORKER
    VOLUME --> WORKER
    GIT --> WORKER
    PIP --> WORKER

    style CODE fill:#4f46e5,color:#fff
    style WORKER fill:#f59e0b,color:#000
    style BIND fill:#16a34a,color:#fff
    style IMAGE fill:#0ea5e9,color:#fff
    style GIT fill:#7c3aed,color:#fff
```

| Mode | Mechanism | Best For | Required Variable |
|---|---|---|---|
| `bind` | Host bind-mount at `/app` | Local dev, bare metal, systemd | `APP_PATH` |
| `image` | Baked into `WORKER_IMAGE` via `COPY` | CI/CD, production | — |
| `volume` | Named Docker volume at `/app` | Containerised Django | `APP_VOLUME_NAME` |
| `git` | `git clone` at startup, `git pull` on restart | Cloud, remote servers | `APP_GIT_URL` |
| `pip` | `pip install APP_PIP_PACKAGE` at startup | Packaged Django apps | `APP_PIP_PACKAGE` |

> [!WARNING]
> **The Multi-Project Scaling Challenge**
> This is exactly the kind of problem that shows why a single shared worker image doesn’t scale well across multiple Django projects. If two projects depend on the same library but require different versions, you’ll inevitably hit conflicts. Here are the main strategies to manage version mismatches:
> 
> **🔹 1. Per‑Project Worker Images (Recommended)**
> - Each project builds its own Celery worker image with its own `requirements.txt` or `poetry.lock`.
> - Workers connect to the shared Redis broker, but run in isolated containers.
> - This way, Project A can use Django==4.2 while Project B uses Django==5.0, without clashing.
> - CI/CD pipelines ensure each worker image is rebuilt with the correct dependencies.
> 
> **🔹 2. Queue Segregation**
> - Use separate queues per project in Redis.
> - Workers only subscribe to their project’s queue.
> - Prevents workers from accidentally consuming tasks from another project that might require incompatible dependencies.

---

## 9. Component Boundaries & Interface Contracts

Each component follows a strict **Interface Contract** (`INTERFACE.md`) ensuring isolation and preventing cross-module dependencies.

```mermaid
graph TB
    subgraph "components/gateway/"
        G_IF["INTERFACE.md"]
        G_COMP["docker-compose.gateway.yml"]
        G_CONF["nginx.conf.template"]
        G_TLS["ssl/ + scripts/"]
        G_TEST["tests/"]
    end

    subgraph "components/brokers/"
        B_IF["INTERFACE.md"]
        B_COMP["docker-compose.brokers.yml"]
        B_TEST["tests/"]
    end

    subgraph "components/workers/"
        W_IF["INTERFACE.md"]
        W_COMP["docker-compose.workers.yml<br/>+ dual-workers.yml<br/>+ kafka-workers.yml<br/>+ asgi.yml"]
        W_DOCK["Dockerfile.base<br/>.full · .mssql · .pdf · .smb"]
        W_CONF["config/<br/>broker_settings.py<br/>celery_config.py<br/>celery_hybrid.py<br/>django_celery_integration.py<br/>path_utils.py<br/>system_tasks.py"]
        W_STRAT["strategies/<br/>broker.*.env<br/>worker.*.env"]
        W_CODE["code-source overlays<br/>code-bind · code-volume · code-git"]
        W_TEST["tests/"]
    end

    subgraph "components/observability/"
        O_IF["INTERFACE.md"]
        O_COMP["docker-compose.monitoring.yml"]
        O_PROM["prometheus/<br/>prometheus.yml.template<br/>alert_rules.yml<br/>alertmanager.yml"]
        O_GRAF["grafana/provisioning/<br/>5 dashboards"]
        O_TEST["tests/"]
    end

    B_COMP -.->|"creates network"| NET["celery-broker-net"]
    G_COMP -.->|"joins"| NET
    W_COMP -.->|"joins"| NET
    O_COMP -.->|"joins"| NET

    style NET fill:#0ea5e9,color:#fff
    style G_IF fill:#f59e0b,color:#000
    style B_IF fill:#f59e0b,color:#000
    style W_IF fill:#f59e0b,color:#000
    style O_IF fill:#f59e0b,color:#000
```

| Component | Responsibility | Boundary Rule |
|---|---|---|
| **Gateway** | TLS termination, rate limiting, reverse proxy, WebSocket proxy | Must not depend on application logic |
| **Brokers** | Message queuing, global state, result storage | Must not depend on workers or monitoring |
| **Workers** | Task execution, code runtime, Flower monitoring | Parametric injection only; project-agnostic |
| **Observability** | Telemetry, dashboards, alerting | Passive observer; no impact on system if it fails |

> [!IMPORTANT]
> **Multi-Mode Ingress Strategy**
> The platform gateway layer is deliberately decoupled to support two distinct ingress modes. Deployment pipelines **must** explicitly choose their ingress strategy based on scale:
> 
> **🔹 1. Static Ingress (Nginx)**
> - **Best For:** Startups, single-team deployments, bare-metal servers, and local environments.
> - **Mechanism:** The built-in, pre-configured Nginx container provides rock-solid rate limiting, static TLS/mTLS termination, and straightforward WebSocket routing for a singular upstream group.
> - **Caution:** Extremely reliable but lacks dynamic reverse-proxying. If you need to route dozens of subdomains dynamically, maintaining static Nginx configurations becomes an anti-pattern.
> 
> **🔹 2. Dynamic Ingress (Traefik / Enterprise Gateways)**
> - **Best For:** Enterprise multi-tenant clusters, automated ephemeral CI/CD environments, and Kubernetes.
> - **Mechanism:** Bypass the generic Nginx components and attach an intelligent edge router like **Traefik**. Traefik hooks directly into Docker daemon labels or Kubernetes Ingress objects to automate `Host` routing, load balancing, and zero-downtime Let's Encrypt certificates.
> - **Caution (Security):** Relying on Docker socket listeners exposes the host to container breakout risks. **Always** deploy dynamic ingress controllers on dedicated edge networks using unprivileged read-only socket proxies, keeping your Celery workers and Redis databases strictly isolated in non-routable internal networks.

---

## 10. Docker Image Hierarchy

Workers use layered Docker images. Each layer adds a capability.

```mermaid
graph BT
    BASE["celery-microservice:base<br/>Python 3.13 + Celery + Redis client<br/>+ Kafka client + Flower<br/>pip==25.1"]
    MSSQL["celery-microservice:mssql<br/>+ pyodbc / SQL Server drivers"]
    PDF["celery-microservice:pdf<br/>+ WeasyPrint / Pillow"]
    SMB["celery-microservice:smb<br/>+ pysmb / paramiko"]
    FULL["celery-microservice:full<br/>All capabilities (legacy)"]

    BASE --> MSSQL
    BASE --> PDF
    BASE --> SMB
    BASE --> FULL

    style BASE fill:#1e293b,color:#fff
    style MSSQL fill:#0ea5e9,color:#fff
    style PDF fill:#7c3aed,color:#fff
    style SMB fill:#16a34a,color:#fff
    style FULL fill:#64748b,color:#fff
```

---

## 11. Observability Pipeline

```mermaid
graph LR
    subgraph "Data Sources"
        REDIS_SVC["Redis"]
        RMQ_SVC["RabbitMQ"]
        CELERY_SVC["Celery Workers"]
        NODE_SVC["Docker Host"]
        NGINX_SVC["Nginx"]
    end

    subgraph "Exporters"
        RE["redis-exporter<br/>:9121"]
        RQE["rabbitmq-exporter<br/>:9419"]
        CE1["celery-exporter-redis<br/>:9808"]
        CE2["celery-exporter-rmq<br/>:9809"]
        NE["node-exporter<br/>:9100"]
        NXE["nginx-exporter<br/>:9113"]
    end

    subgraph "Collection"
        PROM_S["Prometheus<br/>:9090<br/>scrape every 15s<br/>retain 15 days"]
    end

    subgraph "Visualization"
        GRAF_S["Grafana :8300"]
        D1["📊 Celery Tasks"]
        D2["📊 Redis"]
        D3["📊 RabbitMQ"]
        D4["📊 Node Overview"]
        D5["📊 Django + Gunicorn"]
    end

    subgraph "Alerting"
        ALERT_S["Alertmanager :9093"]
        PD["PagerDuty<br/>(critical)"]
        SL["Slack<br/>(warning)"]
        EM["Email<br/>(fallback)"]
    end

    REDIS_SVC --> RE --> PROM_S
    RMQ_SVC --> RQE --> PROM_S
    CELERY_SVC --> CE1 --> PROM_S
    CELERY_SVC --> CE2 --> PROM_S
    NODE_SVC --> NE --> PROM_S
    NGINX_SVC --> NXE --> PROM_S

    PROM_S --> GRAF_S
    GRAF_S --> D1
    GRAF_S --> D2
    GRAF_S --> D3
    GRAF_S --> D4
    GRAF_S --> D5

    PROM_S -->|"alert rules"| ALERT_S
    ALERT_S --> PD
    ALERT_S --> SL
    ALERT_S --> EM

    style ALERT_S fill:#dc2626,color:#fff
```

> [!TIP]
> **Enterprise Observability Recommendation**
> For this platform, we recommend keeping **Prometheus + Grafana** as the default tier (open-source, flexible, and fully self-hosted).
> 
> However, we offer **Datadog integration** as an optional enterprise module for teams that require SaaS-level APM and logging out of the box. 
> 
> **Per-Project Filtering Strategy:** If you share a cluster, it is critical to document the filtering strategy so teams only see their own metrics. Use **Grafana variables** (filtering by `Queue` or `namespace`) or **Datadog tags** (e.g., `project:alpha`) attached to the Celery workers and emitted metrics to achieve multi-tenant metric isolation.

---

## 12. Runtime Abstraction Layer

The platform detaches the **manifest format** from the **execution logic** through a runtime abstraction layer.

```mermaid
graph TD
    subgraph "runtime/ Layer"
        direction TB
        UP["docker/ (core/up.sh)<br/>Docker Compose YAML"]
        POD["podman/up.sh<br/>Podman Compose YAML"]
        K8S["kubernetes/helm/<br/>Helm Chart & K8s Manifests"]
    end

    subgraph "Shared Resources"
        direction LR
        CONF["Python Config Modules<br/>broker_settings.py"]
        IMG["Docker Images<br/>celery-microservice:base"]
    end

    UP --> CONF
    POD --> CONF
    K8S --> CONF
    UP --> IMG
    POD --> IMG
    K8S --> IMG

    style UP fill:#0ea5e9,color:#fff
    style POD fill:#7c3aed,color:#fff
    style K8S fill:#f59e0b,color:#000
    style CONF fill:#16a34a,color:#fff
    style IMG fill:#16a34a,color:#fff
```

| Runtime | Adapter Path | Manifest Format | Autoscaling |
|---|---|---|---|
| **Docker** | `runtime/docker/` (pointer) | `docker-compose.yml` | Manual (`--scale`) |
| **Podman** | `runtime/podman/` (shim) | `docker-compose.yml` | Manual (`--scale`) |
| **Kubernetes** | `runtime/kubernetes/helm/` | Helm (Deployments, StatefulSets) | HPA / KEDA (Queue depth) |

> [!NOTE]
> All runtimes share the same Python configuration files inside the worker container (`components/workers/config/*`). This guarantees that regardless of orchestrator, application behaviour remains identical. When using Kubernetes, `CODE_SOURCE` is locked to `image`.

---

## 13. Complete Directory Structure

```text
django-celery-platform/
│
├── core/                                    # 🧠 Orchestration Brain
│   ├── up.sh                                #    The ONLY entry point
│   ├── modes/                               #    Deploy tier overrides
│   │   ├── minimal.yml                      #      Redis only, no monitoring
│   │   ├── standard.yml                     #      + Prometheus + Grafana
│   │   ├── full.yml                         #      Everything (all brokers + alerting)
│   │   ├── dual-workers.yml                 #      Scales celery-beat to 0 for dual mode
│   │   └── kafka-broker.yml                 #      Scales Redis/RMQ workers to 0 for Kafka
│   └── profiles/                            #    Server sizing
│       ├── sizing.small.env                 #      Low resource constraints
│       ├── sizing.medium.env                #      Balanced defaults
│       └── sizing.large.env                 #      High throughput
│
├── components/
│   ├── brokers/                             # 📨 Message Broker Layer
│   │   ├── INTERFACE.md                     #    Component contract
│   │   ├── CONTRIBUTING.md                  #    Contributor guide
│   │   ├── docker-compose.brokers.yml       #    Redis + RabbitMQ + Kafka
│   │   └── tests/                           #    Smoke tests
│   │
│   ├── gateway/                             # 🌐 Gateway Layer
│   │   ├── INTERFACE.md                     #    Component contract
│   │   ├── CONTRIBUTING.md                  #    Contributor guide
│   │   ├── docker-compose.gateway.yml       #    Nginx reverse proxy
│   │   ├── nginx.conf.template              #    Nginx config template
│   │   ├── ssl/                             #    TLS certificates
│   │   ├── scripts/                         #    Certificate generation scripts
│   │   │   ├── generate_mtls_certs.sh       #      Generate mTLS certs
│   │   │   └── import_mtls_certs.sh         #      Import certs
│   │   └── tests/                           #    Smoke tests
│   │
│   ├── workers/                             # ⚙️ Worker Layer
│   │   ├── INTERFACE.md                     #    Component contract
│   │   ├── CONTRIBUTING.md                  #    Contributor guide
│   │   ├── docker-entrypoint.sh             #    Container entrypoint (CODE_SOURCE dispatch)
│   │   │
│   │   ├── Dockerfile.base                  #    Python 3.13 + Celery + Flower
│   │   ├── Dockerfile.full                  #    All capabilities
│   │   ├── Dockerfile.mssql                 #    + SQL Server support
│   │   ├── Dockerfile.pdf                   #    + WeasyPrint / Pillow
│   │   ├── Dockerfile.smb                   #    + SMB / SSH support
│   │   │
│   │   ├── config/                          #    Reference Celery config modules
│   │   │   ├── broker_settings.py           #      URL builders + get_result_backend()
│   │   │   ├── celery_config.py             #      Host-side Celery apps
│   │   │   ├── celery_hybrid.py             #      Container-side multi-broker apps
│   │   │   ├── django_celery_integration.py #      Django-aware apps + autodiscover
│   │   │   ├── path_utils.py                #      CWE-22 hardened file I/O
│   │   │   └── system_tasks.py              #      Platform health tasks
│   │   │
│   │   ├── strategies/                      #    Broker/worker env selectors
│   │   │   ├── broker.redis.env             #      Redis-only strategy
│   │   │   ├── broker.rabbitmq.env          #      RabbitMQ-only strategy
│   │   │   ├── broker.hybrid.env            #      Redis + RabbitMQ strategy
│   │   │   ├── broker.kafka.env             #      Kafka strategy
│   │   │   ├── worker.single.env            #      Single worker topology
│   │   │   └── worker.dual.env              #      Dual worker topology
│   │   │
│   │   ├── docker-compose.workers.yml       #    Base workers (fast + critical + beat + flower)
│   │   ├── docker-compose.dual-workers.yml  #    Hybrid flower + hybrid beat
│   │   ├── docker-compose.kafka-workers.yml #    Kafka worker + kafka beat + kafka flower
│   │   ├── docker-compose.asgi.yml          #    Daphne + Channel Layer
│   │   │
│   │   ├── docker-compose.workers.code-bind.yml    # CODE_SOURCE overlays
│   │   ├── docker-compose.workers.code-volume.yml  #   for base workers
│   │   ├── docker-compose.workers.code-git.yml     #
│   │   ├── docker-compose.dual-workers.code-*.yml  #   for dual workers
│   │   ├── docker-compose.asgi.code-*.yml          #   for ASGI
│   │   ├── docker-compose.kafka-workers.code-*.yml #   for Kafka workers
│   │   │
│   │   ├── requirements/                    #    Python dependencies
│   │   │   ├── core.txt                     #      Celery + Redis + Kafka + Flower
│   │   │   ├── auth.txt                     #      Authentication packages
│   │   │   ├── mssql.txt                    #      SQL Server drivers
│   │   │   ├── pdf.txt                      #      PDF generation
│   │   │   └── smb.txt                      #      SMB/SSH packages
│   │   └── tests/                           #    Smoke tests
│   │
│   └── observability/                       # 📊 Monitoring Layer
│       ├── INTERFACE.md                     #    Component contract
│       ├── CONTRIBUTING.md                  #    Contributor guide
│       ├── docker-compose.monitoring.yml    #    Prometheus + Grafana + Exporters + Alertmanager
│       ├── prometheus/                      #    Prometheus configs
│       │   ├── prometheus.yml.template      #      Scrape config (envsubst)
│       │   ├── alert_rules.yml              #      Alert rule definitions
│       │   ├── alertmanager.yml             #      Alert routing (PagerDuty/Slack/Email)
│       │   └── docker-entrypoint.sh         #      envsubst runner
│       ├── grafana/provisioning/            #    Auto-provisioned dashboards
│       │   ├── dashboards/                  #      5 JSON dashboard definitions
│       │   │   ├── celery-tasks.json        #        Celery task metrics
│       │   │   ├── redis.json               #        Redis performance
│       │   │   ├── rabbitmq.json            #        RabbitMQ queues
│       │   │   ├── node-overview.json       #        Host system metrics
│       │   │   └── django-gunicorn.json     #        Django + Gunicorn
│       │   └── datasources/                 #      Prometheus data source config
│       └── tests/                           #    Smoke tests
│
├── demo/                                    # 🎮 Contributor Test Environment
│   ├── docker-compose.yml                   #    Self-contained demo stack
│   ├── config/                              #    Redis + RabbitMQ Celery apps
│   ├── demo_app/                            #    Tasks, views, WebSocket consumer
│   └── start.sh / start.bat                 #    Quick start scripts
│
├── docs/                                    # 📚 Documentation
│   ├── README.md                            #    Full deployment reference
│   ├── DEVELOPER_GUIDE.md                   #    Django integration guide
│   ├── ARCHITECTURE_DIAGRAM.md              #    This file
│   ├── UPGRADE.md                           #    Version migration guide
│   ├── FAILURE_MODES.md                     #    Platform triage guide
│   ├── KUBERNETES_PATH.md                   #    Scaling roadmap (Stages 2-5)
│   ├── STRATEGIC_POSITIONING.md             #    Architecture decisions
│   └── Additional_Works.md                  #    OSS modularity plan
│
├── .docker.env                              #    Non-secret defaults (safe to commit)
├── .env.secrets                             #    Generated secrets (NEVER commit)
├── .env.secrets.example                     #    Secrets template
├── .celery-profile.env.example              #    Project profile template
├── init-secrets.sh                          #    Zero-trust secrets generator
├── CHANGELOG.md                             #    Version history
├── LICENSE                                  #    MIT License
└── README.md                                #    Quick start guide
```

---

## 14. Typical Usage Flows

### Flow A — Solo Developer Quick Start

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Init as init-secrets.sh
    participant TLS as generate_mtls_certs.sh
    participant Up as core/up.sh
    participant Stack as Docker Stack

    Dev->>Init: ./init-secrets.sh
    Init-->>Dev: ✅ .env.secrets generated

    Dev->>TLS: ./components/gateway/scripts/generate_mtls_certs.sh localhost
    TLS-->>Dev: ✅ TLS certs in ssl/

    Dev->>Dev: Create celery-profile.env from template

    Dev->>Up: MODE=minimal PROJECT_PROFILE=./celery-profile.env ./core/up.sh
    Up->>Up: Validate dimensions
    Up->>Stack: docker compose up -d
    Stack-->>Dev: ✅ Redis + Nginx + worker-fast + Beat + Flower

    Dev->>Dev: Open http://localhost:5555 (Flower)
    Dev->>Dev: Start dispatching tasks from Django
```

### Flow B — Production Hybrid Deployment

```mermaid
sequenceDiagram
    participant Ops as DevOps Engineer
    participant Up as core/up.sh
    participant Stack as Docker Stack

    Ops->>Ops: Configure celery-profile.env with all project vars
    Ops->>Ops: Set APP_PATH, CELERY_APP_REDIS, CELERY_APP_RABBITMQ

    Ops->>Up: MODE=full BROKER_MODE=hybrid WORKER_MODE=dual<br/>SERVER_PROFILE=large ./core/up.sh
    Up->>Up: Validate: dual requires hybrid ✅
    Up->>Stack: docker compose with 10+ compose fragments
    Stack-->>Ops: ✅ Full stack with dual workers

    Note over Stack: Running services:
    Note over Stack: Redis + RabbitMQ + Nginx
    Note over Stack: worker-fast + worker-critical
    Note over Stack: hybrid-beat + flower-hybrid :5557
    Note over Stack: Prometheus + Grafana + Alertmanager
    Note over Stack: All 6 metric exporters
```

---

## 15. Container Naming Convention

| Container | Name Pattern | Example |
|---|---|---|
| Redis | `celery-redis-shared` | Shared infrastructure (fixed name) |
| RabbitMQ | `celery-rabbitmq-shared` | Shared infrastructure (fixed name) |
| Kafka | `celery-kafka-shared` | Shared infrastructure (fixed name) |
| Nginx | `celery-nginx-shared` | Shared infrastructure (fixed name) |
| Fast Worker | `<PROJECT_NAME>-worker-fast` | `myapp-worker-fast` |
| Critical Worker | `<PROJECT_NAME>-worker-critical` | `myapp-worker-critical` |
| Kafka Worker | `<PROJECT_NAME>-worker-kafka` | `myapp-worker-kafka` |
| Beat | `<PROJECT_NAME>-beat` | `myapp-beat` |
| Flower Redis | `<PROJECT_NAME>-flower-redis` | `myapp-flower-redis` |
| Flower RabbitMQ | `<PROJECT_NAME>-flower-rabbitmq` | `myapp-flower-rabbitmq` |
| Flower Hybrid | `<PROJECT_NAME>-flower-hybrid` | `myapp-flower-hybrid` |
| Flower Kafka | `<PROJECT_NAME>-flower-kafka` | `myapp-flower-kafka` |
| Prometheus | `prometheus-shared` | Shared observability |
| Grafana | `grafana-shared` | Shared observability |
| Alertmanager | `alertmanager-shared` | Shared observability |
| Exporters | `*-exporter-shared` / `celery-exporter-*` | Per-service metrics |

---

## 16. Security Model

```mermaid
graph TD
    subgraph "Public Network"
        CLIENT["Client"]
    end

    subgraph "Edge"
        NGX_SEC["Nginx<br/>TLS 1.2/1.3<br/>mTLS optional<br/>Rate limiting"]
    end

    subgraph "Internal Network (127.0.0.1 bound)"
        REDIS_SEC["Redis<br/>requirepass"]
        RMQ_SEC["RabbitMQ<br/>user/pass auth"]
        KAFKA_SEC["Kafka<br/>PLAINTEXT (internal only)"]
        WORKERS_SEC["Workers<br/>non-root celery user"]
        FLOWER_SEC["Flower<br/>basic_auth"]
        GRAFANA_SEC["Grafana<br/>admin password"]
    end

    subgraph "Secrets Management"
        INIT["init-secrets.sh"]
        SECRETS[".env.secrets<br/>(gitignored)"]
    end

    CLIENT -->|"HTTPS :443"| NGX_SEC
    NGX_SEC -->|"internal"| REDIS_SEC
    NGX_SEC -->|"internal"| WORKERS_SEC
    INIT -->|"generates"| SECRETS
    SECRETS -->|"injected at<br/>compose up"| REDIS_SEC
    SECRETS -->|"injected"| RMQ_SEC
    SECRETS -->|"injected"| FLOWER_SEC
    SECRETS -->|"injected"| GRAFANA_SEC

    style CLIENT fill:#1e293b,color:#fff
    style NGX_SEC fill:#6366f1,color:#fff
    style SECRETS fill:#dc2626,color:#fff
```

| Security Layer | Implementation |
|---|---|
| Network isolation | Internal ports bound to `127.0.0.1` only |
| Transport encryption | TLS 1.2/1.3 at Nginx; mTLS in `MODE=full` |
| Authentication | Redis `requirepass`, RabbitMQ user/pass, Flower `basic_auth`, Grafana admin |
| Process isolation | All workers run as non-root `celery` user |
| Secret management | `init-secrets.sh` generates cryptographic random passwords; `.env.secrets` is gitignored |
| Rate limiting | Configurable via `NGINX_RATE_LIMIT` (default: 10 req/s) |

---

**Version**: 3.1.0
**Project**: django-celery-platform
**Architecture**: Composable Monorepo Component Model
**Last Updated**: 2026-04
**License**: MIT — see LICENSE in the repository root
