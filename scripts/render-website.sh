#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="${VERSION_FILE:-$REPO_ROOT/FIREFOX_VERSION}"
WEBSITE_TEMPLATE="${WEBSITE_TEMPLATE:-$REPO_ROOT/website/index.html.in}"
WEBSITE_OUTPUT="${WEBSITE_OUTPUT:-$REPO_ROOT/website/index.html}"

source "$VERSION_FILE"
: "${VERSION:?VERSION must be set in FIREFOX_VERSION}"

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+)*([ab][0-9]+)?$ ]]; then
    echo "Error: unsupported Firefox version '$VERSION'" >&2
    exit 1
fi

OUTPUT_DIR="$(dirname "$WEBSITE_OUTPUT")"
mkdir -p "$OUTPUT_DIR"
TEMP_OUTPUT="$(mktemp "$OUTPUT_DIR/.index.html.XXXXXX")"

sed "s/@VERSION@/$VERSION/g" "$WEBSITE_TEMPLATE" > "$TEMP_OUTPUT"

if grep -q '@VERSION@' "$TEMP_OUTPUT"; then
    echo "Error: unresolved version placeholder in rendered homepage" >&2
    exit 1
fi

mv "$TEMP_OUTPUT" "$WEBSITE_OUTPUT"
echo "==> Rendered homepage for NightsEdge $VERSION"
