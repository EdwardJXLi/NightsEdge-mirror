#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$REPO_ROOT/artifacts}"
SOURCE_DIR="${SOURCE_DIR:-$REPO_ROOT/mozilla-release}"
UPDATE_URL_BASE="${UPDATE_URL_BASE:-https://nightsedge.hydranet.dev}"
MAR_SIGNING_CERT_NICKNAME="${MAR_SIGNING_CERT_NICKNAME:-NightsEdge MAR Primary}"
PUBLIC_CERT="${PUBLIC_CERT:-$REPO_ROOT/certs/nightsedge-mar-primary.der}"
SIGNMAR="${SIGNMAR:-$SOURCE_DIR/obj-x86_64-pc-linux-gnu/dist/bin/signmar}"
CERTUTIL="${CERTUTIL:-certutil}"

: "${MAR_SIGNING_NSS_DB_B64:?MAR_SIGNING_NSS_DB_B64 must be set}"

source "$REPO_ROOT/FIREFOX_VERSION"
: "${VERSION:?VERSION must be set in FIREFOX_VERSION}"

if [[ ! -x "$SIGNMAR" ]]; then
    echo "Error: native signmar executable not found: $SIGNMAR" >&2
    exit 1
fi
if ! command -v "$CERTUTIL" >/dev/null 2>&1; then
    echo "Error: certutil not found; install libnss3-tools" >&2
    exit 1
fi
if [[ ! -f "$PUBLIC_CERT" ]]; then
    echo "Error: public MAR certificate not found: $PUBLIC_CERT" >&2
    exit 1
fi

SIGNING_ROOT="$(mktemp -d)"
cleanup() {
    rm -rf -- "$SIGNING_ROOT"
}
trap cleanup EXIT

NSS_ARCHIVE="$SIGNING_ROOT/nssdb.tar.gz"
NSS_DB="$SIGNING_ROOT/nssdb"
mkdir -m 0700 "$NSS_DB"

if ! printf '%s' "$MAR_SIGNING_NSS_DB_B64" | base64 --decode > "$NSS_ARCHIVE"; then
    echo "Error: MAR signing database secret is not valid base64" >&2
    exit 1
fi
unset MAR_SIGNING_NSS_DB_B64
if tar -tzf "$NSS_ARCHIVE" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    echo "Error: MAR signing database archive contains an unsafe path" >&2
    exit 1
fi
tar -xzf "$NSS_ARCHIVE" --no-same-owner --no-same-permissions -C "$NSS_DB"
rm -f -- "$NSS_ARCHIVE"
chmod 0600 "$NSS_DB"/*

for db_file in cert9.db key4.db pkcs11.txt; do
    if [[ ! -f "$NSS_DB/$db_file" ]]; then
        echo "Error: MAR signing database archive is missing $db_file" >&2
        exit 1
    fi
done

# Fail before signing if the CI key does not match the public certificate
# compiled into NightsEdge.
SIGNING_CERT="$SIGNING_ROOT/signing-cert.der"
"$CERTUTIL" \
    -L \
    -d "sql:$NSS_DB" \
    -n "$MAR_SIGNING_CERT_NICKNAME" \
    -r > "$SIGNING_CERT"
if ! cmp -s "$SIGNING_CERT" "$PUBLIC_CERT"; then
    echo "Error: MAR signing key does not match $PUBLIC_CERT" >&2
    exit 1
fi

SIGNMAR_LIBRARY_PATH="$(dirname "$SIGNMAR")"
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
    SIGNMAR_LIBRARY_PATH="$SIGNMAR_LIBRARY_PATH:$LD_LIBRARY_PATH"
fi
run_signmar() {
    LD_LIBRARY_PATH="$SIGNMAR_LIBRARY_PATH" "$SIGNMAR" "$@"
}

UPDATE_URL_BASE="${UPDATE_URL_BASE%/}"
TARGETS=(
    linux-x86_64
    linux-aarch64
    windows-x86_64
    macos-x86_64
    macos-aarch64
)

for target in "${TARGETS[@]}"; do
    mar_dir="$ARTIFACTS_DIR/$target/mar"
    mar_file="$mar_dir/nightsedge-${VERSION}-${target}.complete.mar"
    update_xml="$mar_dir/nightsedge-${VERSION}-${target}.update.xml"

    if [[ ! -f "$mar_file" ]]; then
        echo "Error: release MAR not found: $mar_file" >&2
        exit 1
    fi
    if [[ ! -f "$update_xml" ]]; then
        echo "Error: update manifest not found: $update_xml" >&2
        exit 1
    fi

    signed_mar="$SIGNING_ROOT/$(basename "$mar_file").signed"
    run_signmar \
        -d "sql:$NSS_DB" \
        -n "$MAR_SIGNING_CERT_NICKNAME" \
        -s "$mar_file" "$signed_mar"

    # Verification uses the same certificate whose DER bytes were compared
    # with the certificate compiled into the browser above.
    run_signmar \
        -d "sql:$NSS_DB" \
        -n "$MAR_SIGNING_CERT_NICKNAME" \
        -v "$signed_mar"

    mv -f "$signed_mar" "$mar_file"

    mar_hash="$(sha512sum "$mar_file" | cut -d' ' -f1)"
    mar_size="$(stat -c%s "$mar_file")"
    mar_url="$UPDATE_URL_BASE/mar/$target/$(basename "$mar_file")"

    python3 - "$update_xml" "$mar_url" "$mar_hash" "$mar_size" <<'PY'
import re
import sys
from pathlib import Path

xml_path = Path(sys.argv[1])
mar_url, mar_hash, mar_size = sys.argv[2:]
contents = xml_path.read_text()

if f'URL="{mar_url}"' not in contents:
    raise SystemExit(f"{xml_path}: expected MAR URL is missing")

contents, hash_count = re.subn(
    r'hashValue="[^"]*"',
    f'hashValue="{mar_hash}"',
    contents,
)
contents, size_count = re.subn(
    r'size="[0-9]+"',
    f'size="{mar_size}"',
    contents,
)
if hash_count != 1 or size_count != 1:
    raise SystemExit(
        f"{xml_path}: expected one hash and size, got "
        f"{hash_count} hash values and {size_count} sizes"
    )

xml_path.write_text(contents)
PY

    echo "==> Signed and verified $mar_file"
    echo "    SHA-512: $mar_hash"
    echo "    Size:    $mar_size"
done

echo "==> All release MARs are signed and verified"
