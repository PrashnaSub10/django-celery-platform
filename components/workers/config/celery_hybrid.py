"""
celery_hybrid.py — Multi-broker Celery apps for containerised workers.

Provides Celery application instances that connect to the shared
broker containers.  Default hostnames resolve via the
``celery-broker-net`` Docker network and can be overridden via
``REDIS_HOST`` / ``RABBITMQ_HOST`` / ``KAFKA_HOST`` environment variables.

Routing guide
-------------
Redis (``app_redis``)
    Fast, ephemeral work: email notifications, SMS, cache warming,
    real-time push, quick API calls, log processing.

RabbitMQ (``app_rabbitmq``)
    Critical, durable work: payment processing, financial transactions,
    report generation, data synchronisation, long-running batch jobs.
    Tasks survive a worker crash (``task_acks_late=True``).

Kafka (``app_kafka``)
    Streaming, high-throughput work: event ingestion, log aggregation,
    data pipeline stages, analytics events, audit trails.
    Ordered delivery within partitions; durable by default.

Example::

    from config.celery_hybrid import app_redis, app_rabbitmq, app_kafka

    # Fast lane
    app_redis.send_task("tasks.send_email", args=[user_id])

    # Secure vault
    app_rabbitmq.send_task("tasks.process_payment", args=[order_id])

    # Streaming lane
    app_kafka.send_task("tasks.ingest_event", args=[event_payload])
"""

import os

from celery import Celery

from .broker_settings import (
    KAFKA_CONF,
    RABBITMQ_CONF,
    REDIS_CONF,
    get_result_backend,
    kafka_broker_url,
    rabbitmq_broker_url,
    redis_broker_url,
)

__all__ = ["app_redis", "app_rabbitmq", "app_kafka"]

# Container-network hostnames are the defaults; override via env vars
# so the same module works in both Docker and local test environments.
_REDIS_HOST = os.environ.get("REDIS_HOST", "celery-redis-shared")
_RABBITMQ_HOST = os.environ.get("RABBITMQ_HOST", "celery-rabbitmq-shared")
_KAFKA_HOST = os.environ.get("KAFKA_HOST", "celery-kafka-shared")


def _make_apps() -> tuple[Celery, Celery, Celery]:
    """Instantiate all Celery apps, resolving broker URLs at call time.

    Returns:
        A ``(app_redis, app_rabbitmq, app_kafka)`` tuple.

    Raises:
        RuntimeError: If required broker credentials are not set.
    """
    _app_redis = Celery(
        "fast_tasks",
        broker=redis_broker_url(host=_REDIS_HOST),
        backend=get_result_backend(host=_REDIS_HOST),
    )
    _app_redis.conf.update(REDIS_CONF)

    _app_rabbitmq = Celery(
        "critical_tasks",
        broker=rabbitmq_broker_url(host=_RABBITMQ_HOST),
        backend=get_result_backend(host=_REDIS_HOST),
    )
    _app_rabbitmq.conf.update(RABBITMQ_CONF)

    _app_kafka = Celery(
        "streaming_tasks",
        broker=kafka_broker_url(host=_KAFKA_HOST),
        backend=get_result_backend(host=_REDIS_HOST),
    )
    _app_kafka.conf.update(KAFKA_CONF)

    return _app_redis, _app_rabbitmq, _app_kafka


app_redis, app_rabbitmq, app_kafka = _make_apps()
