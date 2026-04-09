"""
system_tasks.py — Platform heartbeat tasks for pipeline verification.

These tasks verify that the Celery worker pipeline is alive end-to-end
(broker → worker → result backend).  They deliberately avoid importing
Django integration so they work in any deployment topology.

Which tasks are registered depends on ``BROKER_MODE``:

- ``redis`` or ``hybrid``    → ``platform.heartbeat`` registered on ``app_redis``
- ``rabbitmq`` or ``hybrid`` → ``platform.critical_heartbeat`` on ``app_rabbitmq``

Usage (from a Django management command or health-check script)::

    from config.system_tasks import redis_heartbeat
    result = redis_heartbeat.delay()
    print(result.get(timeout=10))
"""

import logging
import os

logger = logging.getLogger(__name__)

_BROKER_MODE = os.environ.get("BROKER_MODE", "redis").lower()

# ---------------------------------------------------------------------------
# Redis heartbeat — registered only when Redis is in use
# ---------------------------------------------------------------------------

if _BROKER_MODE in ("redis", "hybrid"):
    from .celery_hybrid import app_redis
    from .broker_settings import REDIS_CONF

    @app_redis.task(
        name="platform.heartbeat",
        bind=True,
        queue=REDIS_CONF["task_default_queue"],
    )
    def redis_heartbeat(self):
        """Verify the Redis worker pipeline is alive."""
        logger.info("Redis heartbeat on node: %s", self.request.hostname)
        return {"status": "ok", "broker": "redis", "node": self.request.hostname}

# ---------------------------------------------------------------------------
# RabbitMQ heartbeat — registered only when RabbitMQ is in use
# ---------------------------------------------------------------------------

if _BROKER_MODE in ("rabbitmq", "hybrid"):
    from .celery_hybrid import app_rabbitmq
    from .broker_settings import RABBITMQ_CONF

    @app_rabbitmq.task(
        name="platform.critical_heartbeat",
        bind=True,
        queue=RABBITMQ_CONF["task_default_queue"],
    )
    def rabbitmq_heartbeat(self):
        """Verify the RabbitMQ worker pipeline is alive."""
        logger.info("RabbitMQ heartbeat on node: %s", self.request.hostname)
        return {"status": "ok", "broker": "rabbitmq", "node": self.request.hostname}

# ---------------------------------------------------------------------------
# Kafka heartbeat — registered only when Kafka is in use
# ---------------------------------------------------------------------------

if _BROKER_MODE == "kafka":
    from .celery_hybrid import app_kafka
    from .broker_settings import KAFKA_CONF

    @app_kafka.task(
        name="platform.streaming_heartbeat",
        bind=True,
        queue=KAFKA_CONF["task_default_queue"],
    )
    def kafka_heartbeat(self):
        """Verify the Kafka worker pipeline is alive."""
        logger.info("Kafka heartbeat on node: %s", self.request.hostname)
        return {"status": "ok", "broker": "kafka", "node": self.request.hostname}