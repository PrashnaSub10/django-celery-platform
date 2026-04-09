# Podman Runtime

Podman is a daemonless container engine that is largely compatible with
Docker Compose via `podman-compose` or Podman's built-in `podman compose`.

## Quick Start

```bash
# From the repo root:
./runtime/podman/up.sh
# Or with dimensions:
MODE=standard BROKER_MODE=redis ./runtime/podman/up.sh
```

## How It Works

`runtime/podman/up.sh` is a thin wrapper around `core/up.sh` that:

1. Sets `CONTAINER_RUNTIME=podman` so compose uses podman
2. Delegates to `core/up.sh` with all arguments forwarded

The same Docker Compose YAML files are used — `podman compose` (Podman 4.x+)
or `podman-compose` can parse standard Docker Compose v3 files.

## Prerequisites

- **Podman 4.x+** with built-in `podman compose` support, OR
- **podman-compose** (`pip install podman-compose`)
- On Linux: no additional requirements
- On macOS: `podman machine init && podman machine start`

## Known Differences from Docker

| Area | Docker | Podman |
|---|---|---|
| Daemon | Requires `dockerd` running | Daemonless (rootless by default) |
| Networking | `docker0` bridge | `cni` or `netavark` |
| `host.docker.internal` | Available natively (macOS/Windows) | Requires `--network slirp4netns:allow_host_loopback=true` or an extra hosts entry |
| Compose | `docker compose` (v2 plugin) | `podman compose` (v4.x+) or `podman-compose` |
| Root vs Rootless | Root by default | Rootless by default |

## Limitations

- **`host.docker.internal`**: The platform uses this to let Nginx and Prometheus
  reach the Django app running on the host. On Podman, you may need to set
  `DJANGO_UPSTREAM_HOST` to your host's IP address explicitly.
- **Volume permissions**: Rootless Podman maps UIDs differently. The `celery`
  user inside the container may need UID mapping adjustments for bind mounts.
