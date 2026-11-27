#!/usr/bin/env bash
#
# Creates a stable self-signed code signing identity for ScreenTap.
#
#   Scripts/setup-signing.sh
#
# Why this matters: an ad-hoc signature ("codesign -s -") gets a new identity on
# every rebuild, so macOS treats every new build as a different application and
# asks for the screen recording permission again. A certificate with a stable code
# requirement keeps the permission across rebuilds.
#
# The identity is stored in a dedicated keychain with a well known password so
# that no interactive prompt is needed while building.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IDENTITY_NAME="ScreenTap SelfSigned"
KEYCHAIN="$HOME/Library/Keychains/screentap.keychain-db"
KEYCHAIN_PASSWORD="screentap"
WORK="$ROOT/.build/signing"

mkdir -p "$WORK"

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "The identity \"$IDENTITY_NAME\" already exists — nothing to do."
    exit 0
fi

echo "==> Generating a self-signed certificate"
cat > "$WORK/openssl.cnf" <<'CONFIG'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = ScreenTap SelfSigned
O = ScreenTap

[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
CONFIG

openssl req -x509 -newkey rsa:2048 -nodes \
    -config "$WORK/openssl.cnf" \
    -keyout "$WORK/signing.key" \
    -out "$WORK/signing.crt" \
    -days 3650 2>/dev/null

echo "==> Creating the keychain $KEYCHAIN"
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

echo "==> Importing the certificate and the key"
security import "$WORK/signing.crt" -k "$KEYCHAIN" -T /usr/bin/codesign -A
security import "$WORK/signing.key" -k "$KEYCHAIN" -T /usr/bin/codesign -A

echo "==> Allowing codesign to use the key without a prompt"
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN" >/dev/null

echo "==> Trusting the certificate for code signing"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/signing.crt"

echo "==> Adding the keychain to the search list"
CURRENT=$(security list-keychains -d user | tr -d '"')
security list-keychains -d user -s $CURRENT "$KEYCHAIN"

rm -f "$WORK/signing.key"

echo
security find-identity -v -p codesigning | grep "$IDENTITY_NAME" || {
    echo "The identity could not be verified." >&2
    exit 1
}
echo "Done. Build with:"
echo "  SCREENTAP_CODESIGN_IDENTITY=\"$IDENTITY_NAME\" ./Scripts/build.sh"
