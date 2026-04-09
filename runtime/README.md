# Runtime Abstraction Layer

The `runtime/` directory contains deployment adapters for different container
orchestration platforms. Each subdirectory is a self-contained deployment
target that shares the same Python config modules (`components/workers/config/`)
but uses platform-native manifest formats.

## Available Runtimes

| Runtime | Entry Point | Status | Manifest Format |
|---|---|---|---|
| **Docker Compose** | `core/up.sh` | ✅ Production-ready | Docker Compose YAML |
| **Podman** | `runtime/podman/up.sh` | ✅ Compatible (thin shim) | Same Compose YAML via `podman-compose` |
| **Kubernetes** | `helm install` | 🚧 Skeleton (April 2026) | Helm chart |

## Architecture

```text
runtime/
├── docker/              ← Points to existing core/up.sh
│   └── README.md
├── podman/              ← Thin shim over docker compose files
│   ├── README.md
│   └── up.sh            ← Swaps docker → podman binary
└── kubernetes/          ← Separate implementation (Helm chart)
    ├── README.md
    └── helm/
        ├── Chart.yaml
        ├── values.yaml  ← Maps to the 6 configuration dimensions
        └── templates/   ← Kubernetes-native manifests
```

## Shared Components

All runtimes share:
- **Python config modules** (`components/workers/config/broker_settings.py`, etc.)
- **Docker images** (`celery-microservice:base`, `:mssql`, `:pdf`, `:smb`)
- **Configuration dimensions** (MODE, BROKER_MODE, WORKER_MODE, etc.)

Runtime-specific:
- Docker/Podman: Compose files, `up.sh`, mode overlays, code-source overlays
- Kubernetes: Helm templates, `values.yaml`, HPA, Ingress, ServiceMonitor

## Bridge: `CODE_SOURCE=image`

The migration path from Docker Compose to Kubernetes is `CODE_SOURCE=image`:

1. Build your worker image in CI/CD (with your Django code baked in)
2. Push to a container registry
3. Reference the image in both `celery-profile.env` (Compose) and `values.yaml` (Helm)

This ensures zero application code changes when moving between runtimes.
