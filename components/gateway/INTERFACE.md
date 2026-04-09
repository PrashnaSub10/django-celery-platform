# Gateway Component Interface Contract

This boundary definition ensures the Gateway module acts purely as networking middleware. It enforces rate limits, TLS/mTLS termination, and WebSocket proxying.

## 📥 Consumes (Inputs)
| Environment Variable | Description |
|----------------------|-------------|
| `DJANGO_UPSTREAM_HOST` | Hostname of the Django WSGI app (Default: `host.docker.internal`) |
| `DJANGO_UPSTREAM_PORT` | Port of the Django WSGI app (Default: `9845`) |
| `DJANGO_ASGI_HOST` | Hostname of the Daphne ASGI app — only used when `ASGI_MODE=true` (Default: `host.docker.internal`) |
| `DJANGO_ASGI_PORT` | Port of the Daphne ASGI app — only used when `ASGI_MODE=true` (Default: `9501`) |
| `NGINX_CLIENT_MAX_BODY_SIZE` | Maximum upload size payload (Default: `100M`) |
| `NGINX_RATE_LIMIT` | Global rate limit applied per IP (Default: `10r/s`) |

When `ASGI_MODE=false` (default), `DJANGO_ASGI_HOST` and `DJANGO_ASGI_PORT` fall back
to the WSGI values — `/ws/` and `/` both route to the same upstream. Use this when
running a unified ASGI server (e.g. Uvicorn) that handles both HTTP and WebSocket.

## 📤 Exposes (Outputs)
- **`:80`** — Unencrypted HTTP traffic (typically redirects to 443).
- **`:443`** — TLS encrypted external traffic.
- **`:8080/stub_status`** — Internal endpoint exposed *only* to the docker network for Prometheus scraping. Not exposed to the host.

## 🕸️ Network State
- **Expects**: `celery-broker-net`.
- **Reason**: Must sit on the same subnet as the Nginx Exporter and Broker nodes if applicable. It defines this network as `external: true` which requires the network to be created prior to boot.

## 🛑 Strict Isolation
- **Does NOT depend on `workers/`**: Gateway must function even if Celery workers crash or are removed.
- **Does NOT depend on `observability/`**: If Prometheus is omitted during deployment, Nginx will still run transparently.
