# Workers Component Interface Contract

The Workers component is the runtime execution engine. It is designed to be highly
parametric, injecting project-specific code and dependencies into standardized
execution environments.

This component has three compose files:
- `docker-compose.workers.yml` — always loaded (Celery workers, Beat, Flower per broker)
- `docker-compose.asgi.yml` — optional, loaded when `ASGI_MODE=true` (Daphne + Channel Layer Redis)
- `docker-compose.dual-workers.yml` — optional, loaded when `WORKER_MODE=dual` (unified Flower + hybrid Beat)

---

## 📥 Consumes (Inputs)

### Always Required
| Variable | Description | Source |
|---|---|---|
| `PROJECT_NAME` | Unique identifier for the application (e.g. `my-app`) | `celery-profile.env` |
| `WORKER_IMAGE` | Docker image to use (e.g. `celery-microservice:base`) | `celery-profile.env` |
| `APP_PATH` | Absolute host path to the Django application code | `celery-profile.env` |
| `CELERY_APP_REDIS` | Import path for the Redis-backed Celery app | `celery-profile.env` |
| `CELERY_APP_RABBITMQ` | Import path for the RabbitMQ-backed Celery app | `celery-profile.env` |
| `REDIS_PASSWORD` | Celery broker Redis authentication | `.env.secrets` |
| `RABBITMQ_USER` / `RABBITMQ_PASSWORD` | RabbitMQ credentials | `.env.secrets` |
| `FLOWER_USER` / `FLOWER_PASSWORD` | Flower UI basic auth | `.env.secrets` |
| `FAST_CONCURRENCY` | Gevent pool concurrency for fast worker | `core/profiles/sizing.*.env` |
| `CRITICAL_CONCURRENCY` | Pool concurrency for critical worker | `core/profiles/sizing.*.env` |

### Dual Worker Mode Only (`WORKER_MODE=dual`)
| Variable | Description | Source |
|---|---|---|
| `FLOWER_PORT_HYBRID` | Host port for unified Flower UI (default: `5557`) | `.docker.env` |

### ASGI Mode Only (`ASGI_MODE=true`)
| Variable | Description | Source |
|---|---|---|
| `ASGI_APPLICATION` | Django ASGI application path (e.g. `config.asgi:application`) | `celery-profile.env` |
| `ASGI_PORT` | Port Daphne listens on inside the container (default: `9501`) | `celery-profile.env` |
| `CHANNELS_REDIS_PASSWORD` | Password for the dedicated Channel Layer Redis | `.env.secrets` |
| `CHANNELS_REDIS_MAXMEMORY` | Max memory for Channel Layer Redis (default: `256mb`) | `.docker.env` |

### Optional
| Variable | Description | Source |
|---|---|---|
| `EXTRA_PIP_PACKAGES` | Space-separated pip packages injected at runtime | Environment / `celery-profile.env` |
| `MEDIA_VOLUME_PATH` | Host path for media file access in critical worker | `.env.secrets` |

---

## 📤 Exposes (Outputs)

| Port | Service | Notes |
|---|---|---|
| `127.0.0.1:5555` | Flower (Redis) | Per-broker worker inspection UI |
| `127.0.0.1:5556` | Flower (RabbitMQ) | Per-broker worker inspection UI |
| `127.0.0.1:5557` | Flower (Hybrid) | Unified UI — only when `WORKER_MODE=dual` |
| `9501` (internal) | Daphne ASGI | Only when `ASGI_MODE=true`. Nginx routes `/ws/` here. |
| `127.0.0.1:6380` | Redis Channel Layer | Only when `ASGI_MODE=true`. Isolated from broker Redis. |

Workers themselves expose no inbound ports — they connect outbound to brokers.

---

## 🕸️ Network State

- **Expects**: `celery-broker-net` (created by `components/brokers/`)
- **DNS hostnames used**: `celery-redis-shared`, `celery-rabbitmq-shared`, `redis-channels` (ASGI only)

---

## 🔀 ASGI / WebSocket Architecture

When `ASGI_MODE=true`, two additional services start:

```
Browser
  │  WSS :443 /ws/
  ▼
Nginx (gateway)
  │  proxies /ws/ → django_asgi upstream
  ▼
Daphne :9501  (django-asgi container)
  │  channel_layer.group_send()
  ▼
Redis Channel Layer :6380  (redis-channels container)
  │  noeviction — messages never dropped
  ▼
Daphne → WebSocket → Browser
```

The Channel Layer Redis runs with `maxmemory-policy noeviction` — this is intentionally
different from the Celery broker Redis (`allkeys-lru`). They must be separate instances.

### Celery → Browser task progress pattern

```python
# In your Celery task:
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync

channel_layer = get_channel_layer()
async_to_sync(channel_layer.group_send)(
    f"task_progress_{task_id}",
    {"type": "task.progress", "percent": 75, "status": "running"}
)
```

```python
# In your Django Channels consumer:
class TaskProgressConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        await self.channel_layer.group_add(
            f"task_progress_{self.scope['url_route']['kwargs']['task_id']}",
            self.channel_name
        )
        await self.accept()

    async def task_progress(self, event):
        await self.send(text_data=json.dumps(event))
```

---

## 🛑 Strict Isolation

- **Does NOT depend on `gateway/`** — Workers process tasks independently of Nginx
- **Does NOT depend on `observability/`** — Workers run regardless of metric scraping
- **ASGI does NOT depend on `rabbitmq`** — Channel Layer uses its own Redis, not RabbitMQ
- **`WORKER_MODE=dual` requires `BROKER_MODE=hybrid`** — enforced by `up.sh` at launch time
- **Only one Beat process must run** — `dual-workers.yml` scales `celery-beat` to 0; `worker-hybrid-beat` takes over
- **Ephemeral worker logs** — `/app/logs` volume should not persist between image versions
