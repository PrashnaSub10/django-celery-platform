#!/bin/bash
# Import mTLS Certificates from Existing NGINX Container
# Usage: ./import_mtls_certs.sh [source_path]

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default source path (Windows path converted to WSL/Linux)
DEFAULT_SOURCE="/mnt/d/NGINX-Container/certs"
SOURCE_PATH="${1:-$DEFAULT_SOURCE}"

echo "🔐 mTLS Certificate Import Script"
echo "=================================="
echo ""

# Check if source exists
if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${YELLOW}⚠️  Source path not found: $SOURCE_PATH${NC}"
    echo ""
    echo "Usage: ./import_mtls_certs.sh [source_path]"
    echo ""
    echo "Examples:"
    echo "  ./import_mtls_certs.sh /mnt/d/NGINX-Container/certs"
    echo "  ./import_mtls_certs.sh /path/to/your/certs"
    echo ""
    exit 1
fi

# Create destination directory
mkdir -p nginx-mtls/certs

echo "📁 Source: $SOURCE_PATH"
echo "📁 Destination: $SCRIPT_DIR/nginx-mtls/certs"
echo ""

# Copy certificates
echo "Copying certificates..."

REQUIRED_FILES=("ca.crt" "ca.key" "server.crt" "server.key")
OPTIONAL_FILES=("client.crt" "client.key" "ca.srl")

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$SOURCE_PATH/$file" ]; then
        cp "$SOURCE_PATH/$file" nginx-mtls/certs/
        echo "  ✓ Copied $file"
    else
        echo -e "${YELLOW}  ⚠️  Missing required file: $file${NC}"
    fi
done

for file in "${OPTIONAL_FILES[@]}"; do
    if [ -f "$SOURCE_PATH/$file" ]; then
        cp "$SOURCE_PATH/$file" nginx-mtls/certs/
        echo "  ✓ Copied $file (optional)"
    fi
done

# Set permissions
echo ""
echo "Setting permissions..."
chmod 644 nginx-mtls/certs/*.crt 2>/dev/null || true
chmod 600 nginx-mtls/certs/*.key 2>/dev/null || true
echo "  ✓ Permissions set"

# Verify certificates
echo ""
echo "Verifying certificates..."

if command -v openssl &> /dev/null; then
    # Check CA certificate
    if [ -f nginx-mtls/certs/ca.crt ]; then
        CA_SUBJECT=$(openssl x509 -in nginx-mtls/certs/ca.crt -noout -subject 2>/dev/null || echo "Error")
        echo "  CA: $CA_SUBJECT"
    fi
    
    # Check server certificate
    if [ -f nginx-mtls/certs/server.crt ]; then
        SERVER_SUBJECT=$(openssl x509 -in nginx-mtls/certs/server.crt -noout -subject 2>/dev/null || echo "Error")
        SERVER_EXPIRY=$(openssl x509 -in nginx-mtls/certs/server.crt -noout -enddate 2>/dev/null || echo "Error")
        echo "  Server: $SERVER_SUBJECT"
        echo "  Expiry: $SERVER_EXPIRY"
    fi
    
    # Verify certificate chain
    if [ -f nginx-mtls/certs/ca.crt ] && [ -f nginx-mtls/certs/server.crt ]; then
        if openssl verify -CAfile nginx-mtls/certs/ca.crt nginx-mtls/certs/server.crt &>/dev/null; then
            echo -e "  ${GREEN}✓ Certificate chain valid${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Certificate chain validation failed${NC}"
        fi
    fi
else
    echo "  ⚠️  OpenSSL not found, skipping verification"
fi

echo ""
echo -e "${GREEN}✅ Certificate import complete!${NC}"
echo ""
echo "📁 Certificates location: $SCRIPT_DIR/nginx-mtls/certs/"
echo ""
echo "Next steps:"
echo "  1. Review nginx-mtls/nginx.conf"
echo "  2. Deploy with: docker-compose -f docker-compose.django.yml up -d"
echo "  3. Test mTLS: See MTLS-SETUP-GUIDE.md"
echo ""
