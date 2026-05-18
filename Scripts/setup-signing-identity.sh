#!/usr/bin/env bash
# Creates a self-signed code-signing identity in the login keychain,
# reused for local builds. Keeps macOS permissions stable across
# rebuilds (unlike ad-hoc signing, which creates a new identity on
# every run → permission reset).
#
# Run once. Afterwards ./Scripts/build-app.sh builds with this identity.
set -euo pipefail

IDENTITY_NAME="Diarize Local Dev"
KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q "\"$IDENTITY_NAME\""; then
    echo "✓ Identity '$IDENTITY_NAME' already exists."
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "\"$IDENTITY_NAME\""
    exit 0
fi

echo "→ Creating self-signed code-signing identity '$IDENTITY_NAME'"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
prompt             = no
x509_extensions    = v3_ca

[ req_distinguished_name ]
CN = $IDENTITY_NAME

[ v3_ca ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# 10-year self-signed cert
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -config "$WORK/cert.cnf" >/dev/null 2>&1

# Pack into PKCS#12 (codesign needs cert+key together)
PASS="diarize-local-dev"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PASS" -name "$IDENTITY_NAME" >/dev/null 2>&1

# Import into login keychain and grant codesign access
security import "$WORK/identity.p12" -k "$KEYCHAIN_PATH" \
    -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Set ACL so codesign can use it without a password prompt
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true

echo "✓ Identity created."
echo ""
echo "Available code-signing identities:"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "\"$IDENTITY_NAME\"" || true
echo ""
echo "You can now build the app with ./Scripts/build-app.sh."
echo "Permissions should now persist across rebuilds."
