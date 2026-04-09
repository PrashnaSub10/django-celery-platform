# Contributing to Gateway Component

This module holds Nginx proxy rules, mTLS generation scripts, and routing logic. 

Because of the architectural boundaries enforced in `INTERFACE.md`, you **do not** need to spin up the entire Celery stack to test a new Nginx rule. You can test Nginx completely in isolation.

## Local Testing Loop

1. **Simulate the Network Dependency:**
   Since Nginx expects `celery-broker-net` to exist (normally provided by the brokers), you must create it manually for the isolated test:
   ```bash
   docker network create celery-broker-net || true
   ```

2. **Boot the Component:**
   Spin up just the gateway module.
   ```bash
   # From the root of django-celery-platform
   docker compose -f components/gateway/docker-compose.gateway.yml up -d
   ```

3. **Verify:**
   Use tools like `curl` to ensure your new rate limits, IP blocks, or headers are firing correctly against localhost:8443.

4. **Tear Down:**
   ```bash
   docker compose -f components/gateway/docker-compose.gateway.yml down
   # Optional: docker network rm celery-broker-net
   ```

## Development Guidelines
- **Modifying `nginx.conf.template`**: 
  - We use `envsubst` to replace environment variables. If you need a new variable, add it to `INTERFACE.md` and declare a safe default fallback: `${NEW_VAR:-default_value}`.
  - Never hardcode host IPs. Always route via environment vars (e.g., `DJANGO_UPSTREAM_HOST`).
- **mTLS changes**: If you alter `scripts/*`, ensure the standard certificate lifecycle is preserved (CA → Server Cert → Client Cert/P12).
