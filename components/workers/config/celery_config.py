"""
celery_config.py — Standalone Celery apps for host-side task dispatch.

Use this file when your Django project runs on the *host machine* (not
inside a container) and needs to dispatch tasks to the containerised
Redis / RabbitMQ brokers.

For the in-container hybrid setup see ``celery_hybrid.py``.
For Django integration (autodiscover_tasks) see ``django_celery_integration.py``.

Example::

    from config.celery_config import app_redis, app_rabbitmq

    app_redis.send_task("tasks.send_notification", args=[user_id])
    app_rabbitmq.send_task("tasks.process_payment", args=[order_id])
"""

from celery import Celery

from .broker_settings import (
    RABBITMQ_CONF,
    REDIS_CONF,
    get_result_backend,
    rabbitmq_broker_url,
    redis_broker_url,
)

__all__ = ["app_redis", "app_rabbitmq"]


def _make_apps() -> tuple[Celery, Celery]:
    """Instantiate both Celery apps, resolving broker URLs at call time.

    Returns:
        A ``(app_redis, app_rabbitmq)`` tuple.

    Raises:
        RuntimeError: If ``REDIS_PASSWORD`` or ``RABBITMQ_PASSWORD`` are not set.
    """
    _app_redis = Celery(
        "fast_tasks",
        broker=redis_broker_url(),
        backend=get_result_backend(),
    )
    _app_redis.conf.update(REDIS_CONF)

    _app_rabbitmq = Celery(
        "critical_tasks",
        broker=rabbitmq_broker_url(),
        backend=get_result_backend(),
    )
    _app_rabbitmq.conf.update(RABBITMQ_CONF)

    return _app_redis, _app_rabbitmq


app_redis, app_rabbitmq = _make_apps()
