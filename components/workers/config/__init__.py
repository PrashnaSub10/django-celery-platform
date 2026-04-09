"""
config — Celery platform configuration package.

Requires Python 3.13+.

Public surface::

    from config.celery_hybrid import app_redis, app_rabbitmq
    from config.celery_config import app_redis, app_rabbitmq
    from config.django_celery_integration import app_redis, app_rabbitmq
    from config.broker_settings import REDIS_CONF, RABBITMQ_CONF
    from config.path_utils import get_log_path, ensure_dir
"""
