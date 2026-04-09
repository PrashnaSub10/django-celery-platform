"""
django_celery_integration.py — Django-aware Celery apps.

Place this file in your Django project as ``config/celery.py``.
It wires all Celery apps to Django settings and enables
``autodiscover_tasks`` so that ``@shared_task`` decorators in any
installed app are picked up automatically.

Django settings integration
---------------------------
All apps call ``config_from_object`` with ``namespace='CELERY'``.
Platform defaults from ``broker_settings.py`` are applied *after*
``config_from_object`` so they are not silently overridden by an
empty or partial Django settings block.

``autodiscover_tasks`` uses the lazy form
``lambda: settings.INSTALLED_APPS`` so it does not evaluate
``INSTALLED_APPS`` at import time, avoiding circular import issues.

Example ``config/__init__.py``::

    from .celery import app_redis, app_rabbitmq, app_kafka

    __all__ = ("app_redis", "app_rabbitmq", "app_kafka")
"""

import os
import logging

from celery import Celery
from django.conf import settings as django_settings

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

logger = logging.getLogger(__name__)


def _make_apps() -> tuple[Celery, Celery, Celery]:
    """Instantiate all Django-aware Celery apps.

    ``DJANGO_SETTINGS_MODULE`` is set inside this function so that
    importing the module without Django configured does not mutate
    global process state.

    Returns:
        A ``(app_redis, app_rabbitmq, app_kafka)`` tuple.
    """
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.production")

    _app_redis = Celery(
        "fast_tasks",
        broker=redis_broker_url(),
        backend=get_result_backend(),
    )
    # config_from_object first, then conf.update so platform defaults
    # win over any absent or partial CELERY_* keys in Django settings.
    _app_redis.config_from_object("django.conf:settings", namespace="CELERY")
    _app_redis.conf.update(REDIS_CONF)
    # Lazy form avoids evaluating INSTALLED_APPS at import time.
    _app_redis.autodiscover_tasks(lambda: django_settings.INSTALLED_APPS)

    _app_rabbitmq = Celery(
        "critical_tasks",
        broker=rabbitmq_broker_url(),
        backend=get_result_backend(),
    )
    _app_rabbitmq.config_from_object("django.conf:settings", namespace="CELERY")
    _app_rabbitmq.conf.update(RABBITMQ_CONF)
    _app_rabbitmq.autodiscover_tasks(lambda: django_settings.INSTALLED_APPS)

    _app_kafka = Celery(
        "streaming_tasks",
        broker=kafka_broker_url(),
        backend=get_result_backend(),
    )
    _app_kafka.config_from_object("django.conf:settings", namespace="CELERY")
    _app_kafka.conf.update(KAFKA_CONF)
    _app_kafka.autodiscover_tasks(lambda: django_settings.INSTALLED_APPS)

    return _app_redis, _app_rabbitmq, _app_kafka


app_redis, app_rabbitmq, app_kafka = _make_apps()
