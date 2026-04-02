#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Parse arguments ---
TARGET="${1:-}"
UPDATE_URL_BASE="${2:-https://updates.example.com}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: generate-mar.sh <target> [update-url-base]"
    echo "Targets: linux-x86_64, linux-aarch64, win-x86_64"
    exit 1
fi

# --- Read version pin ---
source "$REPO_ROOT/FIREFOX_VERSION"

SOURCE_DIR="${SOURCE_DIR:-$REPO_ROOT/mozilla-release}"
OBJ_DIR=$(find "$SOURCE_DIR" -maxdepth 1 -name "obj-*" -type d | head -1)

if [[ -z "$OBJ_DIR" ]]; then
    echo "Error: no obj-* directory found. Run build.sh first."
    exit 1
fi

DIST_DIR="$OBJ_DIR/dist"
MAR_OUTPUT_DIR="$REPO_ROOT/output/mar/$TARGET"
mkdir -p "$MAR_OUTPUT_DIR"

# --- Locate MAR tool ---
MAR_TOOL="$OBJ_DIR/dist/host/bin/mar"
if [[ ! -x "$MAR_TOOL" ]]; then
    echo "Error: MAR tool not found at $MAR_TOOL"
    exit 1
fi

# --- Determine package file ---
case "$TARGET" in
    linux-x86_64|linux-aarch64)
        PACKAGE=$(find "$DIST_DIR" \( -name "*.tar.xz" -o -name "*.tar.bz2" \) | head -1)
        PLATFORM="Linux_${TARGET#linux-}"
        ;;
    win-x86_64)
        PACKAGE=$(find "$DIST_DIR" -name "*.zip" | head -1)
        PLATFORM="WINNT_x86_64"
        ;;
    *)
        echo "Error: unknown target $TARGET"
        exit 1
        ;;
esac

if [[ -z "$PACKAGE" || ! -f "$PACKAGE" ]]; then
    echo "Error: package not found in $DIST_DIR"
    exit 1
fi

# --- Generate MAR ---
echo "==> Generating MAR for $TARGET..."

MAR_FILE="$MAR_OUTPUT_DIR/nightsedge-${VERSION}-${TARGET}.complete.mar"

# Extract package to temp dir for MAR creation
WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT

case "$TARGET" in
    linux-x86_64|linux-aarch64)
        case "$PACKAGE" in
            *.tar.xz)
                tar -xJf "$PACKAGE" -C "$WORK_DIR"
                ;;
            *.tar.bz2)
                tar -xjf "$PACKAGE" -C "$WORK_DIR"
                ;;
            *)
                echo "Error: unsupported Linux package format: $PACKAGE"
                exit 1
                ;;
        esac
        MAR_SOURCE_DIR="$WORK_DIR/firefox"
        ;;
    win-x86_64)
        unzip -q "$PACKAGE" -d "$WORK_DIR"
        MAR_SOURCE_DIR="$WORK_DIR/firefox"
        ;;
esac

MAR="$MAR_TOOL" \
    "$SOURCE_DIR/tools/update-packaging/make_full_update.sh" \
    "$MAR_FILE" \
    "$MAR_SOURCE_DIR"

echo "==> MAR created: $MAR_FILE"

# --- Generate update.xml ---
MAR_HASH=$(sha512sum "$MAR_FILE" | cut -d' ' -f1)
MAR_SIZE=$(stat -c%s "$MAR_FILE")
BUILD_ID=$(cat "$OBJ_DIR/dist/bin/application.ini" | grep "^BuildID=" | cut -d= -f2)
MAR_FILENAME=$(basename "$MAR_FILE")
MAR_URL="${UPDATE_URL_BASE}/mar/${TARGET}/${MAR_FILENAME}"

UPDATE_XML="$MAR_OUTPUT_DIR/update.xml"
cat > "$UPDATE_XML" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update type="minor" displayVersion="hydra-${VERSION}" appVersion="${VERSION}" platformVersion="${VERSION}" buildID="${BUILD_ID}">
    <patch type="complete" URL="${MAR_URL}" hashFunction="sha512" hashValue="${MAR_HASH}" size="${MAR_SIZE}"/>
  </update>
</updates>
EOF

echo "==> update.xml generated: $UPDATE_XML"
echo "    MAR URL:  $MAR_URL"
echo "    SHA-512:  $MAR_HASH"
echo "    Size:     $MAR_SIZE"
