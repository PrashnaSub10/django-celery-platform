# Contributing to Brokers Component

This module sets up Redis and RabbitMQ topologies, persistence volumes, and memory eviction policies.

## Local Testing Loop

You can test database parameter tweaks without bringing online Python workers or Nginx servers.

1. **Provide Secrets:**
   Ensure you have dummy credentials exported in your terminal, or use the `.env.secrets` file at the root.
   ```bash
   export REDIS_PASSWORD=dummy
   export RABBITMQ_USER=dummy
   export RABBITMQ_PASSWORD=dummy
   ```

2. **Boot the Component:**
   ```bash
   # From root of django-celery-platform
   docker compose -f components/brokers/docker-compose.brokers.yml up -d
   ```

3. **Verify:**
   - **Redis:** `docker exec -it celery-redis-shared redis-cli -a dummy ping`
   - **RabbitMQ:** Navigate to `http://localhost:15672` and login with dummy/dummy.

4. **Tear Down:**
   ```bash
   docker compose -f components/brokers/docker-compose.brokers.yml down -v
   ```

## Development Guidelines
- Always ensure `maxmemory` constraints line up with our sizing profiles.
- Any new broker added (e.g., ActiveMQ/Kafka) must expose its ports explicitly in `INTERFACE.md`.
