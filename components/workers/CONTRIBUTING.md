# Contributing to Workers Component

This module manages the execution environment for Celery tasks, including Dockerfiles, entrypoints, and worker pool configurations.

## Local Testing Loop

You can test changes to the worker's base image or entrypoint script without needing a real production database.

1. **Pre-build the Images:**
   If you change a `Dockerfile`, rebuild:
   ```bash
   docker build -t celery-microservice:base -f components/workers/Dockerfile.base components/workers/
   ```

2. **Simulate a Project Profile:**
   Create a dummy `.env` or use the provided `.env.example`:
   ```bash
   export PROJECT_NAME=dev-test
   export APP_PATH=$(pwd)/dummy-app
   export REDIS_HOST=localhost
   ```

3. **Isolated Network:**
   ```bash
   docker network create celery-broker-net || true
   ```

4. **Verify Entrypoint Logic:**
   Test the `EXTRA_PIP_PACKAGES` injection or safety checks:
   ```bash
   docker run --rm -it \
     -e EXTRA_PIP_PACKAGES="pyjokes" \
     celery-microservice:base bash
   ```

## Development Guidelines
- **Keep Layers Small**: Avoid adding heavy libraries to `Dockerfile.base`. Use `Dockerfile.full` or runtime injection for specialized tasks.
- **No Hardcoded App Logic**: The workers must remain project-agnostic. All application-specific logic must live in the `PROJECT_PROFILE`.
- **Healthchecks**: Every worker service defined in `docker-compose.workers.yml` must have a `celery inspect ping` healthcheck.
