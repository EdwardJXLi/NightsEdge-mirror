#!/usr/bin/env bash
set -euo pipefail

# Generates update XML files for the AUS (Application Update Service).
# Run after MAR files have been generated for all targets.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
UPDATE_URL_BASE="${1:-https://updates.example.com}"

source "$REPO_ROOT/FIREFOX_VERSION"

OUTPUT_DIR="$REPO_ROOT/output/update-server"
mkdir -p "$OUTPUT_DIR"

echo "==> Generating AUS update XML files for version $VERSION"

for TARGET in linux-x86_64 linux-aarch64 win-x86_64; do
    MAR_DIR="$REPO_ROOT/output/mar/$TARGET"
    MAR_FILE=$(find "$MAR_DIR" -name "*.complete.mar" 2>/dev/null | head -1)

    if [[ -z "$MAR_FILE" || ! -f "$MAR_FILE" ]]; then
        echo "    SKIP $TARGET — no MAR file found"
        continue
    fi

    MAR_HASH=$(sha512sum "$MAR_FILE" | cut -d' ' -f1)
    MAR_SIZE=$(stat -c%s "$MAR_FILE")
    MAR_FILENAME=$(basename "$MAR_FILE")
    MAR_URL="${UPDATE_URL_BASE}/mar/${TARGET}/${MAR_FILENAME}"

    # Determine platform string for AUS path
    case "$TARGET" in
        linux-x86_64)   AUS_PLATFORM="Linux_x86_64-gcc3" ;;
        linux-aarch64)  AUS_PLATFORM="Linux_aarch64-gcc3" ;;
        win-x86_64)     AUS_PLATFORM="WINNT_x86_64-msvc" ;;
    esac

    TARGET_DIR="$OUTPUT_DIR/$AUS_PLATFORM"
    mkdir -p "$TARGET_DIR"

    cat > "$TARGET_DIR/update.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update type="minor" displayVersion="hydra-${VERSION}" appVersion="${VERSION}" platformVersion="${VERSION}" buildID="0">
    <patch type="complete" URL="${MAR_URL}" hashFunction="sha512" hashValue="${MAR_HASH}" size="${MAR_SIZE}"/>
  </update>
</updates>
EOF

    echo "    OK $TARGET -> $TARGET_DIR/update.xml"
done

echo "==> Done. Deploy $OUTPUT_DIR to your update server."
