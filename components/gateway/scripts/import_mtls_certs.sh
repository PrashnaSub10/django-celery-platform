#!/bin/bash
# ============================================================
# import_mtls_certs.sh — Import existing TLS/mTLS certificates
# ============================================================
# Copies certificates from an existing source directory into
# components/gateway/ssl/ — the exact path the compose volume
# mount (./ssl) expects.
#
# Usage:
#   ./scripts/import_mtls_certs.sh [source_path]
#   ./scripts/import_mtls_certs.sh /path/to/your/certs
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolves to components/gateway/ssl/ — matches compose volume mount ./ssl
DEST_DIR="${SCRIPT_DIR}/../ssl"

# Default source path
DEFAULT_SOURCE="/mnt/d/NGINX-Container/certs"
SOURCE_PATH="${1:-$DEFAULT_SOURCE}"

echo "mTLS Certificate Import"
echo "======================="
echo ""

# Check if source exists
if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${YELLOW}Warning: Source path not found: $SOURCE_PATH${NC}"
    echo ""
    echo "Usage: ./scripts/import_mtls_certs.sh [source_path]"
    echo ""
    echo "Examples:"
    echo "  ./scripts/import_mtls_certs.sh /mnt/d/NGINX-Container/certs"
    echo "  ./scripts/import_mtls_certs.sh /path/to/your/certs"
    echo ""
    exit 1
fi

# Create destination directory
mkdir -p "$DEST_DIR"

echo "Source:      $SOURCE_PATH"
echo "Destination: ${DEST_DIR}"
echo ""

# Copy certificates
echo "Copying certificates..."

REQUIRED_FILES=("ca.crt" "ca.key" "server.crt" "server.key")
OPTIONAL_FILES=("client.crt" "client.key" "ca.srl" "fullchain.pem" "privkey.pem")

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$SOURCE_PATH/$file" ]; then
        cp "$SOURCE_PATH/$file" "$DEST_DIR/"
        echo "  Copied $file"
    else
        echo -e "${YELLOW}  Missing required file: $file${NC}"
    fi
done

for file in "${OPTIONAL_FILES[@]}"; do
    if [ -f "$SOURCE_PATH/$file" ]; then
        cp "$SOURCE_PATH/$file" "$DEST_DIR/"
        echo "  Copied $file (optional)"
    fi
done

# Nginx expects fullchain.pem = server.crt + ca.crt chain.
# Synthesize it if server.crt and ca.crt were imported but fullchain.pem was not.
if [ ! -f "${DEST_DIR}/fullchain.pem" ] && [ -f "${DEST_DIR}/server.crt" ] && [ -f "${DEST_DIR}/ca.crt" ]; then
    cat "${DEST_DIR}/server.crt" "${DEST_DIR}/ca.crt" > "${DEST_DIR}/fullchain.pem"
    echo "  Synthesized fullchain.pem from server.crt + ca.crt"
fi

# Nginx expects privkey.pem. Alias server.key if privkey.pem is absent.
if [ ! -f "${DEST_DIR}/privkey.pem" ] && [ -f "${DEST_DIR}/server.key" ]; then
    cp "${DEST_DIR}/server.key" "${DEST_DIR}/privkey.pem"
    echo "  Copied server.key → privkey.pem"
fi

# Set permissions
echo ""
echo "Setting permissions..."
chmod 644 "${DEST_DIR}"/*.crt 2>/dev/null || true
chmod 644 "${DEST_DIR}"/*.pem 2>/dev/null || true
chmod 600 "${DEST_DIR}"/*.key 2>/dev/null || true
echo "  Permissions set"

# Verify certificates
echo ""
echo "Verifying certificates..."

if command -v openssl &> /dev/null; then
    if [ -f "${DEST_DIR}/ca.crt" ]; then
        CA_SUBJECT=$(openssl x509 -in "${DEST_DIR}/ca.crt" -noout -subject 2>/dev/null || echo "Error")
        echo "  CA: $CA_SUBJECT"
    fi

    if [ -f "${DEST_DIR}/fullchain.pem" ]; then
        SERVER_SUBJECT=$(openssl x509 -in "${DEST_DIR}/fullchain.pem" -noout -subject 2>/dev/null || echo "Error")
        SERVER_EXPIRY=$(openssl x509 -in "${DEST_DIR}/fullchain.pem" -noout -enddate 2>/dev/null || echo "Error")
        echo "  Server: $SERVER_SUBJECT"
        echo "  Expiry: $SERVER_EXPIRY"
    fi

    if [ -f "${DEST_DIR}/ca.crt" ] && [ -f "${DEST_DIR}/fullchain.pem" ]; then
        if openssl verify -CAfile "${DEST_DIR}/ca.crt" "${DEST_DIR}/fullchain.pem" &>/dev/null; then
            echo -e "  ${GREEN}Certificate chain valid${NC}"
        else
            echo -e "  ${YELLOW}Warning: certificate chain validation failed${NC}"
        fi
    fi
else
    echo "  openssl not found — skipping verification"
fi

echo ""
echo -e "${GREEN}Certificate import complete.${NC}"
echo ""
echo "Certificates location: ${DEST_DIR}/"
echo ""
echo "Next steps:"
echo "  1. Launch the platform: ./core/up.sh MODE=minimal BROKER_MODE=redis ..."
echo "  2. Test HTTPS:  curl -k https://localhost/health"
echo "  3. Test mTLS:   curl -k --cert ${DEST_DIR}/client.crt --key ${DEST_DIR}/client.key https://localhost/api/"
echo ""
