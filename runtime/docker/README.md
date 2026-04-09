# Docker Compose Runtime

This is the **default and primary runtime** for the Django Celery Platform.

## Entry Point

The Docker Compose runtime uses the existing `core/up.sh` launcher.
No files in this directory are needed — everything lives in `core/` and `components/`.

```bash
# From the repo root:
MODE=standard BROKER_MODE=redis ./core/up.sh
```

## Why This Directory Exists

This README is a placeholder for structural consistency with the `runtime/`
abstraction layer. The Docker Compose implementation is mature and lives in:

- `core/up.sh` — Smart Launcher (orchestration brain)
- `core/modes/` — Deploy tier overrides (minimal/standard/full)
- `core/profiles/` — Server sizing (small/medium/large)
- `components/*/docker-compose.*.yml` — Service definitions

See [docs/ARCHITECTURE_DIAGRAM.md](../../docs/ARCHITECTURE_DIAGRAM.md) for
the full compose file layering diagram.
