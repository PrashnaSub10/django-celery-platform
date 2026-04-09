# Kubernetes Runtime (Helm Chart)

Deploy the Django Celery Platform on Kubernetes using Helm.

## Status

🚧 **Skeleton** — structure and values defined, templates are placeholders.
Full implementation scheduled for the enterprise readiness session.

## Quick Start (once implemented)

```bash
# Add your worker image to values.yaml
# Install the chart:
helm install my-celery-platform ./runtime/kubernetes/helm \
  --namespace celery-platform \
  --create-namespace \
  --set workerImage=your-registry.com/your-app:latest \
  --set django.settingsModule=config.settings.production

# Check status:
helm status my-celery-platform -n celery-platform
kubectl get pods -n celery-platform

# Upgrade:
helm upgrade my-celery-platform ./runtime/kubernetes/helm \
  --namespace celery-platform \
  -f my-overrides.yaml

# Uninstall:
helm uninstall my-celery-platform -n celery-platform
```

## Architecture Mapping

The Helm chart maps the platform's 6 dimensions to `values.yaml`:

| Compose Dimension | Helm Equivalent |
|---|---|
| `MODE` | `mode: minimal\|standard\|full` |
| `BROKER_MODE` | `brokerMode: redis\|rabbitmq\|hybrid\|kafka` |
| `WORKER_MODE` | `workerMode: single\|dual` |
| `SERVER_PROFILE` | `resources:` blocks per component |
| `CODE_SOURCE` | Always `image` (the only mode for K8s) |
| `RESULT_BACKEND` | `resultBackend: redis\|django-db\|postgres\|none` |

## What's Shared with Docker Compose

- **Python config modules** — `broker_settings.py`, `celery_hybrid.py`, etc.
  are baked into the worker image and work identically in K8s pods.
- **Docker images** — same `celery-microservice:*` images.
- **Environment variables** — same `REDIS_HOST`, `BROKER_MODE`, etc.

## What's Kubernetes-Native

- **Deployments** instead of compose services
- **Services + Ingress** instead of port bindings
- **HPA (KEDA)** instead of `--scale` flags
- **Secrets** objects instead of `.env.secrets`
- **PVCs** instead of named volumes
- **ServiceMonitor** instead of Prometheus scrape configs

## Prerequisites

- Kubernetes 1.28+
- Helm 3.12+
- A container registry with your worker image
- (Optional) KEDA for queue-depth autoscaling
- (Optional) cert-manager for TLS
