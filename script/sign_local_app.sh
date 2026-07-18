#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <app-bundle> <bundle-identifier>" >&2
  exit 2
fi

APP_BUNDLE="$1"
BUNDLE_ID="$2"
if [[ ! -d "$APP_BUNDLE" || ! "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  echo "A valid app bundle and reverse-DNS bundle identifier are required." >&2
  exit 2
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_DIR="$ROOT_DIR/.local-signing"
KEYCHAIN="$SIGNING_DIR/flow-control.keychain-db"
PASSWORD_FILE="$SIGNING_DIR/keychain-password"
CERTIFICATE_NAME="Flow Control Local Development"

umask 077
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

bootstrap_identity() {
  local openssl_path
  openssl_path="$(command -v openssl || true)"
  if [[ -z "$openssl_path" ]]; then
    echo "OpenSSL is required once to create Flow Control's local signing identity." >&2
    exit 1
  fi
  if ! "$openssl_path" pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    echo "OpenSSL 3 or newer is required once to create Flow Control's local signing identity." >&2
    exit 1
  fi

  local private_key certificate archive password
  private_key="$SIGNING_DIR/local-signing.key"
  certificate="$SIGNING_DIR/local-signing.crt"
  archive="$SIGNING_DIR/local-signing.p12"
  password="$($openssl_path rand -hex 32)"

  local bootstrap_complete=false
  cleanup_bootstrap() {
    local status=$?
    rm -f "$private_key" "$certificate" "$archive"
    if [[ "$bootstrap_complete" != true ]]; then
      /usr/bin/security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
      rm -f "$KEYCHAIN" "$PASSWORD_FILE"
    fi
    trap - EXIT
    exit "$status"
  }
  trap cleanup_bootstrap EXIT

  printf '%s' "$password" >"$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"

  "$openssl_path" req -x509 -newkey rsa:3072 -sha256 -nodes \
    -keyout "$private_key" \
    -out "$certificate" \
    -subj "/CN=$CERTIFICATE_NAME/" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -days 3650 >/dev/null 2>&1
  "$openssl_path" pkcs12 -export -legacy \
    -inkey "$private_key" \
    -in "$certificate" \
    -out "$archive" \
    -passout "pass:$password" >/dev/null 2>&1

  /usr/bin/security create-keychain -p "$password" "$KEYCHAIN"
  /usr/bin/security unlock-keychain -p "$password" "$KEYCHAIN"
  /usr/bin/security import "$archive" \
    -k "$KEYCHAIN" \
    -P "$password" \
    -T /usr/bin/codesign >/dev/null
  /usr/bin/security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$password" \
    "$KEYCHAIN" >/dev/null

  bootstrap_complete=true
  rm -f "$private_key" "$certificate" "$archive"
  trap - EXIT
}

if [[ -e "$KEYCHAIN" || -e "$PASSWORD_FILE" ]]; then
  if [[ ! -f "$KEYCHAIN" || ! -f "$PASSWORD_FILE" ]]; then
    echo "Flow Control's local signing state is incomplete. Remove .local-signing and run again." >&2
    exit 1
  fi
else
  bootstrap_identity
fi

password="$(<"$PASSWORD_FILE")"
/usr/bin/security unlock-keychain -p "$password" "$KEYCHAIN"
lock_keychain_on_exit() {
  local status=$?
  trap - EXIT
  /usr/bin/security lock-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  exit "$status"
}
trap lock_keychain_on_exit EXIT

certificate_sha1="$(
  /usr/bin/security find-certificate \
    -c "$CERTIFICATE_NAME" \
    -Z \
    "$KEYCHAIN" | /usr/bin/awk '/SHA-1 hash:/{print $NF; exit}'
)"
if [[ ! "$certificate_sha1" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  echo "Flow Control's local signing certificate is unavailable or invalid." >&2
  exit 1
fi

designated_requirement="=designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$certificate_sha1\""
/usr/bin/codesign \
  --force \
  --sign "$certificate_sha1" \
  --keychain "$KEYCHAIN" \
  --identifier "$BUNDLE_ID" \
  --requirements "$designated_requirement" \
  "$APP_BUNDLE"

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict \
  --requirements "identifier \"$BUNDLE_ID\" and certificate leaf = H\"$certificate_sha1\"" \
  "$APP_BUNDLE"
