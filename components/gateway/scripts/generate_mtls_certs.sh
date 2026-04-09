#!/bin/bash
# ============================================================
# generate_mtls_certs.sh — Self-signed TLS + mTLS certificates
# ============================================================
# Generates certificates into nginx/ssl/ (the path Nginx expects).
# For production, replace server.crt/key with Let's Encrypt certs.
#
# Usage:
#   ./scripts/generate_mtls_certs.sh [domain]
#   ./scripts/generate_mtls_certs.sh yourdomain.com
# ============================================================

set -euo pipefail

DOMAIN="${1:-localhost}"
CERT_DIR="./nginx/ssl"

echo "Creating certificate directory: $CERT_DIR"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# ── CA ───────────────────────────────────────────────────────
echo "Generating CA key and certificate..."
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=Internal-CA"

# ── Server certificate with SAN (required by modern browsers) ─
echo "Generating server certificate for domain: $DOMAIN"
openssl genrsa -out fullchain.key 4096

cat > server_ext.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl req -new -key fullchain.key -out server.csr \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN}"
openssl x509 -req -days 825 -in server.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -extfile server_ext.cnf -extensions v3_req \
  -out server.crt

# Nginx expects fullchain.pem = server cert + CA chain
cat server.crt ca.crt > fullchain.pem
cp fullchain.key privkey.pem

# ── Client certificate (for mTLS API callers) ────────────────
echo "Generating client certificate..."
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=api-client"
openssl x509 -req -days 825 -in client.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client.crt

# ── Permissions ──────────────────────────────────────────────
chmod 644 -- *.crt *.pem ca.srl 2>/dev/null || true
chmod 600 -- *.key

# ── Cleanup temp files ───────────────────────────────────────
rm -f server.csr client.csr server_ext.cnf

echo ""
echo "✓ Certificates generated in $CERT_DIR"
echo ""
echo "  fullchain.pem  — Nginx ssl_certificate (server + CA chain)"
echo "  privkey.pem    — Nginx ssl_certificate_key"
echo "  ca.crt         — CA certificate (distribute to mTLS API clients)"
echo "  client.crt/key — Client certificate for testing mTLS"
echo ""
echo "For production, replace fullchain.pem + privkey.pem with Let's Encrypt:"
echo "  sudo certbot certonly --standalone -d ${DOMAIN}"
echo "  cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ./nginx/ssl/"
echo "  cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem   ./nginx/ssl/"
echo ""
echo "Test self-signed HTTPS:"
echo "  curl -k https://localhost:8443/health"
echo ""
echo "Test mTLS with client cert:"
echo "  curl -k --cert $CERT_DIR/client.crt --key $CERT_DIR/client.key https://localhost:8443/api/"
