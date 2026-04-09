# 🔐 mTLS Certificate Setup Guide

## What is mTLS?

**Mutual TLS (mTLS)** provides two-way authentication:
- Server proves its identity to clients (normal HTTPS)
- Clients prove their identity to server (mutual authentication)

## 📋 Quick Setup

### Option 1: Copy Existing Certificates

If you have certificates from `D:\NGINX-Container\certs\`:

```bash
# Copy certificates to nginx-mtls/certs/
cp /path/to/NGINX-Container/certs/* ./nginx-mtls/certs/
```

### Option 2: Generate New Certificates

```bash
cd nginx-mtls/certs

# 1. Generate CA (Certificate Authority)
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=MyCA"

# 2. Generate Server Certificate
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=yourdomain.com"
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt

# 3. Generate Client Certificate (for testing)
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=client1"
openssl x509 -req -days 365 -in client.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out client.crt

# Set permissions
chmod 644 *.crt
chmod 600 *.key
```

## 🔧 Architecture: 4-Server-Block Design

The Nginx config uses **four server blocks** to separate concerns cleanly.
There are **no `if ($ssl_client_verify ...)`** directives anywhere —
enforcement is handled by `ssl_verify_client` at the TLS handshake level,
which is the correct pattern (the "if is evil" anti-pattern is fully avoided).

### Port 80 — HTTP Redirect

All HTTP traffic is redirected to HTTPS. No content served here.

```nginx
server {
    listen 80;
    return 301 https://$host$request_uri;
}
```

### Port 8080 — Stub Status (Internal Metrics)

Only reachable inside the Docker network. `nginx-exporter` scrapes this
for Prometheus. This port is NOT published to the host (`expose:` not `ports:`).

```nginx
server {
    listen 8080;
    location /stub_status { stub_status; allow 172.16.0.0/12; deny all; }
}
```

### Port 443 — HTTPS with Optional mTLS (Browser + WebSocket)

Handles all regular HTTPS traffic, including WebSocket upgrades.
`ssl_verify_client optional` means clients **may** present a certificate,
but it is not required. Certificate info is forwarded as headers.

```nginx
server {
    listen 443 ssl;
    ssl_verify_client optional;
    ssl_client_certificate /etc/nginx/certs/ca.crt;

    # WebSocket — route to Daphne (ASGI)
    location /ws/ {
        proxy_pass http://daphne_app;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400s;   # keep WebSocket alive
        proxy_buffering off;
    }

    # HTTP — route to Gunicorn (WSGI)
    location / {
        proxy_pass http://gunicorn_app;
    }

    # mTLS cert info forwarded as headers (available in Django + Channels)
    proxy_set_header X-SSL-Client-Verify $ssl_client_verify;
    proxy_set_header X-SSL-Client-DN     $ssl_client_s_dn;
    proxy_set_header X-SSL-Client-CN     $ssl_client_s_dn_cn;
}
```

### Port 8443 — HTTPS with Strict mTLS (API Gateway)

Machine-to-machine only. `ssl_verify_client on` causes Nginx to **reject
the TLS handshake** if no valid client certificate is presented — no
application code is reached for uncertified clients.

```nginx
server {
    listen 8443 ssl;
    ssl_verify_client on;
    ssl_client_certificate /etc/nginx/certs/ca.crt;

    location /api/ { proxy_pass http://gunicorn_app; }
    location /     { return 403; }
}
```

Use port 8443 for: CI/CD pipelines, partner integrations, internal services,
or any endpoint where you want to guarantee the client identity at the
network level before hitting application code.

## 🧪 Testing mTLS

### Test port 443 (optional mTLS) without a client certificate:

```bash
# Regular HTTP — works, no cert needed
curl --cacert nginx-mtls/certs/ca.crt https://your-server/

# WebSocket connection test (needs wscat: npm install -g wscat)
wscat --ca nginx-mtls/certs/ca.crt \
      --connect wss://your-server/ws/chat/test-room/
```

### Test port 443 with a client certificate:

```bash
# Headers X-SSL-Client-CN / X-SSL-Client-Verify are set in the request
curl --cert nginx-mtls/certs/client.crt \
     --key  nginx-mtls/certs/client.key \
     --cacert nginx-mtls/certs/ca.crt \
     https://your-server/
```

### Test port 8443 (strict mTLS) without a certificate — should be rejected at TLS handshake:

```bash
# No cert → TLS handshake fails (not a 403, the connection is dropped)
curl --cacert nginx-mtls/certs/ca.crt https://your-server:8443/api/
# Expected: curl: (56) OpenSSL SSL_read: error ... or similar TLS error
```

### Test port 8443 with a valid client certificate:

```bash
curl --cert nginx-mtls/certs/client.crt \
     --key  nginx-mtls/certs/client.key \
     --cacert nginx-mtls/certs/ca.crt \
     https://your-server:8443/api/
# Expected: 200 or your API response
```

### Test port 8443 base path (should return 403):

```bash
curl --cert nginx-mtls/certs/client.crt \
     --key  nginx-mtls/certs/client.key \
     --cacert nginx-mtls/certs/ca.crt \
     https://your-server:8443/
# Expected: 403 Forbidden (only /api/ is routed, / returns 403)
```

## 📁 Required Files

```
nginx-mtls/
├── nginx.conf          # NGINX configuration
└── certs/
    ├── ca.crt          # Certificate Authority (public)
    ├── ca.key          # CA private key (keep secure!)
    ├── server.crt      # Server certificate (public)
    ├── server.key      # Server private key (keep secure!)
    ├── client.crt      # Client certificate (for testing)
    └── client.key      # Client private key (for testing)
```

## 🔐 Security Best Practices

1. **Protect Private Keys**:
   ```bash
   chmod 600 nginx-mtls/certs/*.key
   ```

2. **Use Strong Passwords** (if encrypting keys):
   ```bash
   openssl rsa -aes256 -in server.key -out server.key.encrypted
   ```

3. **Regular Certificate Rotation**:
   - Renew certificates before expiry
   - Keep track of expiration dates

4. **Separate CA for Production**:
   - Don't use self-signed certs in production
   - Use proper CA (Let's Encrypt, DigiCert, etc.)

## 🌐 Production Deployment

### With Let's Encrypt (Free SSL):

```bash
# Install Certbot
sudo apt install certbot

# Get certificate
sudo certbot certonly --standalone -d yourdomain.com

# Update nginx.conf to use Let's Encrypt certs
ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
```

### With Custom CA:

1. Generate certificates as shown above
2. Distribute CA certificate to all clients
3. Generate unique client certificates for each client
4. Set `ssl_verify_client on` for strict mTLS

## 🔍 Debugging

### Check certificate validity:

```bash
# Check server certificate
openssl x509 -in nginx-mtls/certs/server.crt -text -noout

# Check client certificate
openssl x509 -in nginx-mtls/certs/client.crt -text -noout

# Verify certificate chain
openssl verify -CAfile nginx-mtls/certs/ca.crt nginx-mtls/certs/server.crt
```

### Check NGINX logs:

```bash
# View mTLS-specific logs
docker exec nginx-mtls-prod tail -f /var/log/nginx/access.log

# Check for SSL errors
docker exec nginx-mtls-prod tail -f /var/log/nginx/error.log
```

## 📊 Client Certificate Info in Django

### In Django views (WSGI / Gunicorn):

Nginx forwards certificate info as HTTP headers. Django surfaces these in
`request.META` with the `HTTP_` prefix and hyphens replaced by underscores.

```python
# In Django views.py
def my_view(request):
    verify_status = request.META.get('HTTP_X_SSL_CLIENT_VERIFY', 'NONE')
    client_cn     = request.META.get('HTTP_X_SSL_CLIENT_CN', '')
    client_dn     = request.META.get('HTTP_X_SSL_CLIENT_DN', '')

    if verify_status == 'SUCCESS':
        # Client authenticated via mTLS
        print(f"Authenticated client: {client_cn}")
    else:
        # No client certificate or invalid (port 443 only — port 8443 rejects at TLS)
        print("No valid client certificate")
```

### In Django Channels consumers (ASGI / Daphne):

WebSocket connections land on port 443 (ssl_verify_client optional).
Daphne surfaces HTTP headers in `scope["headers"]` as a list of
`(bytes, bytes)` tuples.

```python
# In myapp/consumers/secure_consumer.py
from channels.generic.websocket import AsyncWebsocketConsumer

class SecureConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        headers = dict(self.scope.get("headers", []))

        client_verify = headers.get(b"x-ssl-client-verify", b"NONE").decode()
        client_cn     = headers.get(b"x-ssl-client-cn", b"").decode()

        if client_verify == "SUCCESS":
            # Client presented a valid certificate through port 443
            print(f"WebSocket client CN: {client_cn}")
        else:
            # No cert — acceptable on port 443, reject here if you want cert-only WS
            # await self.close(code=4403)
            pass

        await self.accept()
```

> For WebSocket connections that **require** a client certificate, route them
> through port 8443 instead of port 443. The TLS handshake will enforce the
> cert before the WebSocket upgrade is attempted.

## 🆘 Troubleshooting

### "SSL certificate problem":
- Check certificate paths in nginx.conf
- Verify certificates exist in nginx-mtls/certs/
- Check file permissions

### "403 Forbidden" on secure endpoints:
- Client needs valid certificate
- Check `ssl_verify_client` setting
- Verify client cert is signed by CA

### "Connection refused":
- Check if NGINX container is running
- Verify port 443 is exposed
- Check firewall rules

## 📚 Additional Resources

- [NGINX mTLS Documentation](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [OpenSSL Certificate Guide](https://www.openssl.org/docs/)
- Original NGINX-Container: `D:\NGINX-Container\`

---

**For beginners**: Use Mode 1 (Optional mTLS) - it's the safest default!
