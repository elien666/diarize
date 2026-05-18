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

# ── Already exists? ────────────────────────────────────────────────────────────
if security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep -q "\"$IDENTITY_NAME\""; then
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

# Pack into PKCS#12 (codesign needs cert + key together).
# Use legacy encryption so macOS security import (which uses Apple's own TLS
# stack) can read it — OpenSSL 3 defaults to AES-256 which macOS rejects.
PASS="diarize-local-dev"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PASS" -name "$IDENTITY_NAME" \
    -legacy >/dev/null 2>&1

# Import into login keychain, allow codesign + security tool access
security import "$WORK/identity.p12" -k "$KEYCHAIN_PATH" \
    -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security

# ── Set ACL so codesign can use the key without a password prompt ───────────
# set-key-partition-list requires the keychain's own unlock password
# (your macOS login password). We try empty first (works when keychain has no
# password), then prompt interactively.
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: \
       -s -k "" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    echo ""
    echo "  The keychain needs your login password to allow codesign access."
    echo "  (This is a one-time prompt — the password is not stored anywhere.)"
    echo -n "  Keychain password: "
    read -rs KPWD
    echo ""
    if ! security set-key-partition-list -S apple-tool:,apple:,codesign: \
           -s -k "$KPWD" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
        echo "⚠ Could not set ACL (wrong password or MDM restriction)."
        echo "  codesign will show a password dialog on each build — that is OK."
        echo "  Permissions will still be stable as long as you click 'Always Allow'."
    fi
fi

echo ""
echo "✓ Identity created."
echo ""
echo "Available code-signing identities:"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "\"$IDENTITY_NAME\"" || true
echo ""
echo "You can now build the app with ./Scripts/build-app.sh."
echo "Permissions will persist across rebuilds."
