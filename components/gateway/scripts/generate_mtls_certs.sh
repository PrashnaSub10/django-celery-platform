#!/bin/bash
# ============================================================
# generate_mtls_certs.sh — Self-signed TLS + mTLS certificates
# ============================================================
# Writes certificates to components/gateway/ssl/ — the exact
# path the compose volume mount (./ssl) and smoke test expect.
# For production, replace fullchain.pem/privkey.pem with real certs.
#
# Usage (run from any directory):
#   ./components/gateway/scripts/generate_mtls_certs.sh [domain]
#   ./components/gateway/scripts/generate_mtls_certs.sh yourdomain.com
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${1:-localhost}"
# Resolves to components/gateway/ssl/ — matches compose volume mount ./ssl
CERT_DIR="${SCRIPT_DIR}/../ssl"

# ── Preflight: openssl ────────────────────────────────────────
if ! command -v openssl > /dev/null 2>&1; then
    echo "ERROR: openssl is required but not found."
    echo "   Ubuntu/Debian:  sudo apt install openssl"
    echo "   macOS:          brew install openssl"
    echo "   RHEL/CentOS:    sudo yum install openssl"
    echo "   Alpine:         apk add openssl"
    exit 1
fi

# ── Overwrite protection ──────────────────────────────────────
if [ -f "${CERT_DIR}/fullchain.pem" ] || [ -f "${CERT_DIR}/privkey.pem" ]; then
    echo "Certificates already exist in ${CERT_DIR}."
    echo "   Delete them and re-run to regenerate:"
    echo "   rm ${CERT_DIR}/fullchain.pem ${CERT_DIR}/privkey.pem"
    exit 0
fi

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
echo "✓ Certificates generated in ${CERT_DIR}"
echo ""
echo "  fullchain.pem  — Nginx ssl_certificate (server + CA chain)"
echo "  privkey.pem    — Nginx ssl_certificate_key"
echo "  ca.crt         — CA certificate (distribute to mTLS API clients)"
echo "  client.crt/key — Client certificate for testing mTLS"
echo ""
echo "For production, replace fullchain.pem + privkey.pem with Let's Encrypt:"
echo "  sudo certbot certonly --standalone -d ${DOMAIN}"
echo "  cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ${CERT_DIR}/"
echo "  cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem   ${CERT_DIR}/"
echo ""
echo "Test self-signed HTTPS:"
echo "  curl -k https://localhost:443/health"
echo ""
echo "Test mTLS with client cert:"
echo "  curl -k --cert ${CERT_DIR}/client.crt --key ${CERT_DIR}/client.key https://localhost:443/api/"
