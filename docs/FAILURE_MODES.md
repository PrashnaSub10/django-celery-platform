# 💥 Failure Mode Documentation

This document encodes platform engineering knowledge. It doesn't just describe *how* things work, but how they **fail**, *why* they fail, and exactly what to do when they do.

---

## 1. The "Silent Disappearance"

**Failure:** Tasks are dispatched successfully from Django, but they never execute and no error is logged.

**Cause:**
You are likely using **Redis** as your broker, and the Redis instance has hit its memory limit. By default, Redis uses an `allkeys-lru` or `volatile-lru` eviction policy. Under memory pressure, it will silently delete older task data to make room for new data.

**Mitigation:**
1. **Strategic:** Use RabbitMQ (`BROKER_MODE=rabbitmq` or `hybrid`) for mission-critical tasks (emails, payments). RabbitMQ pauses publishers instead of dropping data under memory pressure.
2. **Tactical:** Increase `REDIS_MEMORY_LIMIT` in `.docker.env` and monitor the `evicted_keys` metric in Grafana.
3. **Application Level:** Ensure you aren't storing massive payloads (e.g., base64 images) inside the Celery task arguments. Pass database IDs instead.

---

## 2. The "60-Second Drop"

**Failure:** WebSocket connections (or long-polling HTTP requests) consistently disconnect after exactly 60 seconds.

**Cause:**
Nginx's default `proxy_read_timeout` is 60 seconds. If neither the client nor the ASGI server sends any data within this timeframe, Nginx assumes the upstream service is dead and violently closes the connection.

**Mitigation:**
1. Set `proxy_read_timeout 86400s;` specifically on your `/ws/` location block in `nginx.conf.template`. 
2. Ensure `proxy_send_timeout` is also increased.
3. *Note: We have already implemented this in the default Nginx template for the `/ws/` route.*

---

## 3. The "Queue Backlog Avalanche"

**Failure:** The RabbitMQ queue depth grows indefinitely. Processing speed is a fraction of task ingestion speed.

**Cause:**
Workers are blocked. This usually happens when workers process tasks that rely on third-party APIs (like sending emails) which are responding slowly. Because we use `prefetch_multiplier=1` for critical queues, the worker cannot fetch new tasks until the slow one is acknowledged.

**Mitigation:**
1. **Scale Workers:** Increase `CRITICAL_CONCURRENCY` in your sizing profile (e.g., switch from `small` to `medium`).
2. **Timeouts:** Ensure you are setting explicit timeouts on all `requests.get()` inside your tasks.
3. **Monitor:** Set up Prometheus alerts on `rabbitmq_queue_messages` to alert you *before* the backlog becomes fatal.

---

## 4. The "OOM Worker Crash"

**Failure:** A worker container restarts unexpectedly. The container exit code is `137` or `OOMKilled` in docker inspect.

**Cause:**
Python's memory management can be leaky, especially when processing large datasets or utilizing heavy libraries (like Pandas or PDF engines). The task itself doesn't crash, but the OS kills the process because it requested too much RAM.

**Mitigation:**
1. **Stabilize:** Our templates inherently use `--max-memory-per-child`. Ensure `FAST_MAX_MEMORY` and `CRITICAL_MAX_MEMORY` in your sizing profile accurately reflect your server limits.
2. **Isolate:** If a specific task is a known memory hog, route it to a specialized queue and spin up a dedicated worker just for that queue with strict resources.

---

## 5. Flower Shows "Offline" Workers

**Failure:** Flower starts up and you can log in, but no workers show up in the "Workers" tab, even though `docker logs` shows the worker processing tasks.

**Cause:**
Flower and the Celery Worker are actually connected to completely different broker endpoints. This often happens if your `celery-profile.env` points `CELERY_APP_REDIS` to a Django configuration that uses a hardcoded fallback instead of the environment variables injected by Docker Compose.

**Mitigation:**
1. Verify `config.celery_hybrid` uses `os.environ['REDIS_HOST']` and NOT `localhost`.
2. Ensure you are looking at the correct Flower instance (`:5555` is for Redis, `:5556` gives RabbitMQ workers).
