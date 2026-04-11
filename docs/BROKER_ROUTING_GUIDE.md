# Celery Broker Routing Guide (For Developers & Freshers)

Welcome to the **Django Celery Platform**! If you are a developer integrating a new Django project (a "Spoke") into our shared infrastructure (the "Hub"), you might be wondering: *"Which broker should I use? RabbitMQ or Redis? And what exactly is Hybrid mode?"*

This guide breaks down exactly how to think about, configure, and code your task queues so that your background jobs never drop, crash, or collide with other teams.

---

## 1. The Tale of Two Brokers

The infrastructure you just connected to is running both **Redis** and **RabbitMQ** under the hood. They are not competing—they are built for entirely different jobs.

### 🔴 Redis (Fast, Ephemeral, In-Memory)
- **The Vibe:** A lightning-fast sports car. It holds all its data in memory.
- **The Strengths:** Blazing fast message passing. Excellent for caching and background notifications.
- **The Catch:** If the server violently crashes, any task currently sitting in the Redis queue and not yet processed *might be lost*.
- **Use Cases:** Sending welcome emails, updating user metrics caching, thumbnail generation, non-critical push notifications.

### 🟠 RabbitMQ (Durable, Acknowledged, Disk-Backed)
- **The Vibe:** An armored bank truck. It writes messages to disk and demands a digital signature when a task is finished.
- **The Strengths:** Guaranteed delivery. If a Celery worker crashes halfway through processing a task, RabbitMQ instantly notices the missing *ACK* (acknowledgment) and puts the task securely back in the queue for another worker to try.
- **The Catch:** Slower than Redis because it guarantees data safety.
- **Use Cases:** Processing Stripe payments, issuing refunds, critical PDF generation, database state migrations.

---

## 2. Understanding Your Deployment Modes

When you deploy your application against our platform, your Operations team will set a `BROKER_MODE`. Here is what that means for you:

1. **`BROKER_MODE=redis` (Standard Startup)**
   Your Django app only connects to Redis. You use it for everything. Simple, frictionless, and Handles 85% of standard web app use cases.
2. **`BROKER_MODE=hybrid` (Enterprise Dual-Worker)**
   Your Django app connects to **both** Redis and RabbitMQ simultaneously. We spin up two distinct Celery workers for you:
   - `{project_name}-worker-fast`: Reads from Redis.
   - `{project_name}-worker-critical`: Reads from RabbitMQ.

---

## 3. How to Code Task Routing (Hybrid Mode)

If you are using Hybrid mode, you need to explicitly tell Django which tasks go to which broker.

### Step 3.1: Configure `celery.py` in your Django Project
You must define your queues and point your Celery app to route matching tasks correctly.

```python
# my_project/celery.py
import os
from kombu import Queue, Exchange
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'my_project.settings')

app = Celery('my_project')
app.config_from_object('django.conf:settings', namespace='CELERY')

# IMPORTANT: Always prefix your queues with your Project Name for Multi-Tenancy!
app.conf.task_queues = (
    Queue('my_project_fast', Exchange('my_project_fast'), routing_key='my_project_fast'),
    Queue('my_project_critical', Exchange('my_project_critical'), routing_key='my_project_critical'),
)

# Route tasks automatically based on the queue name!
app.conf.task_routes = {
    'my_project.tasks.send_welcome_email': {'queue': 'my_project_fast'},
    'my_project.tasks.process_stripe_payment': {'queue': 'my_project_critical'},
}

app.autodiscover_tasks()
```

### Step 3.2: Write the Tasks (`tasks.py`)
Now, simply write your functions. Django Celery will look at the `task_routes` defined above and automatically send the payment task to RabbitMQ, and the email task to Redis!

```python
# my_project/tasks.py
from celery import shared_task

@shared_task
def send_welcome_email(user_id):
    # This automatically drops into the REDIS queue (fast, ephemeral)
    print(f"Sending email to {user_id}")

@shared_task(acks_late=True) 
def process_stripe_payment(invoice_id):
    # This automatically drops into the RABBITMQ queue (durable, safe)
    # The `acks_late=True` means RabbitMQ won't delete the message 
    # until the function completely finishes without throwing an exception!
    print(f"Processing payment for invoice {invoice_id}")
```

---

## 4. Freshers' Survival Guide (Reality Checks)

1. **The "Does It Involve Money?" Rule:** If the task involves billing a customer, modifying critical financial state, or generating a legal document—**Use RabbitMQ (`critical`).** If it's a "nice to have" like a push notification—**Use Redis (`fast`).**
2. **Never Drop The Prefix:** In a multi-tenant Hub, multiple teams are using the same central Redis broker. If you name your queue `tasks`, and Team Beta names their queue `tasks`, your worker will randomly steal their tasks and violently crash. **Always use `{project_name}_fast`**.
3. **`acks_late=True` is your safety net:** For RabbitMQ critical tasks, always use `acks_late=True`. This tells RabbitMQ: *"Do not delete this message from the queue just because the worker picked it up. Wait until the worker successfully returns."*
