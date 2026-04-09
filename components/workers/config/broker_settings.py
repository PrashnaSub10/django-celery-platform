"""
broker_settings.py — Shared Celery configuration constants.

Centralises the two broker configurations so that celery_config.py,
celery_hybrid.py, and django_celery_integration.py all read from one
place.  Import this module; never instantiate Celery here.

Requires Python 3.13+.
"""

import os
from types import MappingProxyType

__all__ = [
    "redis_broker_url",
    "redis_backend_url",
    "rabbitmq_broker_url",
    "kafka_broker_url",
    "get_result_backend",
    "REDIS_CONF",
    "RABBITMQ_CONF",
    "KAFKA_CONF",
]


# ---------------------------------------------------------------------------
# URL builders
# ---------------------------------------------------------------------------

def redis_broker_url(*, host: str | None = None) -> str:
    """Return the Redis broker URL (DB 0).

    Args:
        host: Override ``REDIS_HOST``.  Defaults to the env var value.

    Raises:
        RuntimeError: If ``REDIS_PASSWORD`` is not set in the environment.
    """
    password = _require_env("REDIS_PASSWORD")
    resolved_host = host or os.environ.get("REDIS_HOST", "localhost")
    return f"redis://:{password}@{resolved_host}:6379/0"


def redis_backend_url(*, host: str | None = None) -> str:
    """Return the Redis result-backend URL (DB 1).

    Args:
        host: Override ``REDIS_HOST``.  Defaults to the env var value.

    Raises:
        RuntimeError: If ``REDIS_PASSWORD`` is not set in the environment.
    """
    password = _require_env("REDIS_PASSWORD")
    resolved_host = host or os.environ.get("REDIS_HOST", "localhost")
    return f"redis://:{password}@{resolved_host}:6379/1"


def rabbitmq_broker_url(*, host: str | None = None) -> str:
    """Return the RabbitMQ AMQP broker URL.

    Args:
        host: Override ``RABBITMQ_HOST``.  Defaults to the env var value.

    Raises:
        RuntimeError: If ``RABBITMQ_PASSWORD`` is not set in the environment.
    """
    user = os.environ.get("RABBITMQ_USER", "admin")
    password = _require_env("RABBITMQ_PASSWORD")
    resolved_host = host or os.environ.get("RABBITMQ_HOST", "localhost")
    return f"amqp://{user}:{password}@{resolved_host}:5672//"


def kafka_broker_url(*, host: str | None = None) -> str:
    """Return the Kafka broker URL for kombu's confluentkafka transport.

    Args:
        host: Override ``KAFKA_HOST``.  Defaults to the env var value.

    The URL scheme ``confluentkafka://`` is handled by
    ``kombu.transport.confluentkafka``.  The ``confluent-kafka``
    Python package must be installed (included in requirements/core.txt).
    """
    resolved_host = host or os.environ.get("KAFKA_HOST", "localhost")
    resolved_port = os.environ.get("KAFKA_PORT", "9092")
    return f"confluentkafka://{resolved_host}:{resolved_port}"


# ---------------------------------------------------------------------------
# Shared conf dicts — immutable to prevent accidental mutation by callers
# ---------------------------------------------------------------------------

#: Configuration applied to the Redis / fast-task Celery app.
REDIS_CONF: MappingProxyType[str, object] = MappingProxyType({
    "task_default_queue": "redis_queue",
    "task_serializer": "json",
    "accept_content": ["json"],
    "result_serializer": "json",
    "timezone": "UTC",
    "enable_utc": True,
    "task_track_started": True,
    "task_time_limit": 300,
    "task_soft_time_limit": 240,
})

#: Configuration applied to the RabbitMQ / critical-task Celery app.
RABBITMQ_CONF: MappingProxyType[str, object] = MappingProxyType({
    "task_default_queue": "rabbitmq_queue",
    "task_serializer": "json",
    "accept_content": ["json"],
    "result_serializer": "json",
    "timezone": "UTC",
    "enable_utc": True,
    "task_track_started": True,
    "task_acks_late": True,
    "worker_prefetch_multiplier": 1,
    "task_time_limit": 1800,
    "task_soft_time_limit": 1500,
    "task_reject_on_worker_lost": True,
})

#: Configuration applied to the Kafka / streaming-task Celery app.
#: Kafka provides ordered, durable, high-throughput message delivery.
#: The ``confluent-kafka`` transport is used via kombu.
KAFKA_CONF: MappingProxyType[str, object] = MappingProxyType({
    "task_default_queue": "kafka_queue",
    "task_serializer": "json",
    "accept_content": ["json"],
    "result_serializer": "json",
    "timezone": "UTC",
    "enable_utc": True,
    "task_track_started": True,
    "task_time_limit": 600,
    "task_soft_time_limit": 540,
    "worker_prefetch_multiplier": 1,
})


# ---------------------------------------------------------------------------
# Result backend resolver
# ---------------------------------------------------------------------------

def get_result_backend(*, host: str | None = None) -> str:
    """Return the result backend URL based on ``RESULT_BACKEND`` env var.

    Supported modes:
        ``redis`` (default) — Redis DB 1 via ``redis_backend_url()``.
        ``django-db`` — ``django-db://`` (requires ``django-celery-results``).
        ``postgres`` — Direct PostgreSQL via ``DATABASE_URL`` env var.
        ``none`` — Disables result storage (``'disabled'``).

    Args:
        host: Override for the Redis host when ``RESULT_BACKEND=redis``.

    Returns:
        A backend URL string suitable for ``Celery(backend=...)``.

    Raises:
        RuntimeError: If ``RESULT_BACKEND=postgres`` but ``DATABASE_URL``
            is not set.
        ValueError: If ``RESULT_BACKEND`` is not a recognised mode.
    """
    mode = os.environ.get("RESULT_BACKEND", "redis").lower()
    if mode == "redis":
        return redis_backend_url(host=host)
    if mode == "django-db":
        return "django-db://"
    if mode == "postgres":
        url = os.environ.get("DATABASE_URL")
        if not url:
            raise RuntimeError(
                "RESULT_BACKEND=postgres requires DATABASE_URL to be set."
            )
        return f"db+{url}"
    if mode == "none":
        return "disabled"
    raise ValueError(
        f"RESULT_BACKEND='{mode}' is not supported. "
        "Use: redis, django-db, postgres, or none."
    )


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _require_env(key: str) -> str:
    """Return ``os.environ[key]``, raising a descriptive error when absent.

    Args:
        key: Environment variable name.

    Raises:
        RuntimeError: With a human-readable message naming the missing variable.
    """
    value = os.environ.get(key)
    if not value:
        raise RuntimeError(
            f"Required environment variable '{key}' is not set. "
            "Ensure .env.secrets has been sourced (run ./init-secrets.sh)."
        )
    return value
