#!/usr/bin/env bash
# Erstellt eine selbst-signierte Code-Signing-Identity im Login-Keychain,
# die für lokale Builds wiederverwendet wird. Macht macOS-Permissions stabil
# über Rebuilds hinweg (anders als ad-hoc -, das bei jedem Lauf eine neue
# Identität erzeugt → Permission-Reset).
#
# Einmalig ausführen. Danach baut ./Scripts/build-app.sh mit dieser Identity.
set -euo pipefail

IDENTITY_NAME="Diarize Local Dev"
KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q "\"$IDENTITY_NAME\""; then
    echo "✓ Identity '$IDENTITY_NAME' existiert bereits."
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "\"$IDENTITY_NAME\""
    exit 0
fi

echo "→ Erstelle selbst-signierte Code-Signing-Identity '$IDENTITY_NAME'"

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

# 10-Jahre selbstsigniertes Cert
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -config "$WORK/cert.cnf" >/dev/null 2>&1

# In PKCS#12 packen (codesign braucht Cert+Key zusammen)
PASS="diarize-local-dev"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PASS" -name "$IDENTITY_NAME" >/dev/null 2>&1

# In den Login-Keychain importieren und codesign Zugriff geben
security import "$WORK/identity.p12" -k "$KEYCHAIN_PATH" \
    -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# ACL setzen damit codesign ohne Passwort-Prompt nutzen kann
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true

echo "✓ Identity erstellt."
echo ""
echo "Verfügbare Code-Signing-Identitäten:"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "\"$IDENTITY_NAME\"" || true
echo ""
echo "Du kannst jetzt mit ./Scripts/build-app.sh die App bauen."
echo "Permissions sollten ab jetzt über Rebuilds erhalten bleiben."
