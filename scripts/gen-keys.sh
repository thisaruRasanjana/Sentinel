#!/usr/bin/env bash
# scripts/gen-keys.sh
# Generates the RSA key pair, self-signed certificate, and PKCS12 keystore
# used by the token-issuer service. Run this once per environment.
# The generated files are intentionally excluded from Git via .gitignore.

set -euo pipefail

OUT_DIR="$(dirname "$0")/../token-issuer/resources"
mkdir -p "$OUT_DIR"

KEY="$OUT_DIR/private.key"
CERT="$OUT_DIR/public.crt"
KS="$OUT_DIR/keystore.p12"
PASS="${KEYSTORE_PASSWORD:-ballerina}"
ALIAS="sentinel"

echo "Generating RSA 2048-bit private key..."
openssl genrsa -out "$KEY" 2048

echo "Generating self-signed certificate (365 days)..."
openssl req -new -x509 -key "$KEY" -out "$CERT" -days 365 \
  -subj "/CN=sentinel/O=Sentinel/C=US"

echo "Bundling into PKCS12 keystore..."
openssl pkcs12 -export \
  -in "$CERT" \
  -inkey "$KEY" \
  -name "$ALIAS" \
  -out "$KS" \
  -passout "pass:$PASS"

echo ""
echo "Done. Files written to $OUT_DIR:"
ls -lh "$OUT_DIR"
echo ""
echo "Override the keystore password at runtime by setting:"
echo "  KEYSTORE_PASSWORD=<your-password> ./scripts/gen-keys.sh"
