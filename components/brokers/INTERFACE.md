# Brokers Component Interface Contract

This boundary definition ensures the Brokers module acts exactly as message queues and parameter stores, entirely abstracted from the applications using them.

## 📥 Consumes (Inputs)
| Environment Variable | Description |
|----------------------|-------------|
| `REDIS_PASSWORD` | Secures the Redis instance |
| `RABBITMQ_USER` | Admin user for RabbitMQ |
| `RABBITMQ_PASSWORD` | Admin password for RabbitMQ |

*Note: These variables MUST be supplied via the root `.env.secrets` mechanism.*

## 📤 Exposes (Outputs)
- **`:6379`** — Redis primary connection port.
- **`:5672`** — RabbitMQ AMQP queue connection port.
- **`:15672`** — RabbitMQ Management Web UI.

## 🕸️ Network State
- **Owns**: `celery-broker-net`.
- **Reason**: This module explicitly *creates* the isolated subnet that the Gateway, Workers, and Observability layers plug into.

## 🛑 Strict Isolation
- **Does NOT depend on `workers/`**: Can boot perfectly fine without any workers listening.
- **Does NOT depend on `gateway/`**: Web UI is available unencrypted on localhost for developers before Nginx is ready.
- **Does NOT depend on `observability/`**: Exporter configurations exist externally in the monitoring component.
