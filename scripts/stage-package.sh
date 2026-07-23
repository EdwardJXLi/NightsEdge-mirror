#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "Usage: stage-package.sh <target>"
    echo "Targets: linux-x86_64, linux-aarch64, windows-x86_64, macos-x86_64, macos-aarch64"
    exit 1
fi

source "$REPO_ROOT/FIREFOX_VERSION"

: "${VERSION:?VERSION must be set in FIREFOX_VERSION}"

case "$TARGET" in
    linux-x86_64)
        OBJ_PATTERN="obj-x86_64-pc-linux-gnu"
        ARTIFACT_DIR="$REPO_ROOT/artifacts/linux-x86_64"
        ;;
    linux-aarch64)
        OBJ_PATTERN="obj-aarch64-unknown-linux-gnu"
        ARTIFACT_DIR="$REPO_ROOT/artifacts/linux-aarch64"
        ;;
    windows-x86_64)
        OBJ_PATTERN="obj-x86_64-pc-windows-msvc"
        ARTIFACT_DIR="$REPO_ROOT/artifacts/windows-x86_64"
        ;;
    macos-x86_64)
        OBJ_PATTERN="obj-x86_64-apple-darwin"
        ARTIFACT_DIR="$REPO_ROOT/artifacts/macos-x86_64"
        ;;
    macos-aarch64)
        OBJ_PATTERN="obj-aarch64-apple-darwin"
        ARTIFACT_DIR="$REPO_ROOT/artifacts/macos-aarch64"
        ;;
    *)
        echo "Error: unknown target $TARGET"
        exit 1
        ;;
esac

ARTIFACT_PREFIX="nightsedge-${VERSION}-${TARGET}"

OBJ_DIR="$(find "$REPO_ROOT/mozilla-release" -maxdepth 1 -name "$OBJ_PATTERN" -type d | head -1)"
if [[ -z "$OBJ_DIR" ]]; then
    echo "Error: no build output found for $TARGET"
    exit 1
fi

# package_name.txt names the real package; dist also holds helper zips
# (*.xpt_artifacts.zip, *.update_framework_artifacts.zip) a blind glob can grab.
PACKAGE="$OBJ_DIR/dist/$(cat "$OBJ_DIR/dist/package_name.txt" 2>/dev/null || true)"
if [[ ! -f "$PACKAGE" ]]; then
    PACKAGE="$(find "$OBJ_DIR/dist" -maxdepth 1 -type f \( -name '*.tar.xz' -o -name '*.tar.bz2' -o -name '*.zip' -o -name '*.dmg' \) ! -name '*_artifacts.zip' | head -1)"
fi
if [[ -z "$PACKAGE" || ! -f "$PACKAGE" ]]; then
    echo "Error: no package archive found in $OBJ_DIR/dist"
    exit 1
fi
echo "==> Selected package: $PACKAGE"

case "$PACKAGE" in
    *.tar.xz) PACKAGE_SUFFIX="tar.xz" ;;
    *.tar.bz2) PACKAGE_SUFFIX="tar.bz2" ;;
    *.zip) PACKAGE_SUFFIX="zip" ;;
    *.dmg) PACKAGE_SUFFIX="dmg" ;;
    *)
        echo "Error: unsupported package format: $PACKAGE"
        exit 1
        ;;
esac

mkdir -p "$ARTIFACT_DIR"

write_sha256() {
    local artifact="$1"
    local artifact_dir
    local artifact_name

    artifact_dir="$(dirname "$artifact")"
    artifact_name="$(basename "$artifact")"
    (
        cd "$artifact_dir"
        sha256sum "$artifact_name" > "$artifact_name.sha256"
    )
    echo "==> SHA-256: $artifact.sha256"
}

FINAL_PACKAGE="$ARTIFACT_DIR/${ARTIFACT_PREFIX}.${PACKAGE_SUFFIX}"
cp "$PACKAGE" "$FINAL_PACKAGE"
echo "==> Final package: $FINAL_PACKAGE"
write_sha256 "$FINAL_PACKAGE"

# mach package emits the NSIS installer at dist/*.installer.exe
if [[ "$TARGET" == "windows-x86_64" ]]; then
    INSTALLER="$(find "$OBJ_DIR/dist" -maxdepth 1 -type f -name '*.installer.exe' | head -1)"
    if [[ -n "$INSTALLER" ]]; then
        FINAL_INSTALLER="$ARTIFACT_DIR/${ARTIFACT_PREFIX}.installer.exe"
        cp "$INSTALLER" "$FINAL_INSTALLER"
        echo "==> Staged installer: $FINAL_INSTALLER"
        write_sha256 "$FINAL_INSTALLER"
    else
        echo "==> No installer .exe found in $OBJ_DIR/dist (zip-only build)"
    fi
fi

PACKAGE_NAME_FILE="$OBJ_DIR/dist/package_name.txt"
if [[ -f "$PACKAGE_NAME_FILE" ]]; then
    FINAL_PACKAGE_NAME_FILE="$ARTIFACT_DIR/${ARTIFACT_PREFIX}.package_name.txt"
    cp "$PACKAGE_NAME_FILE" "$FINAL_PACKAGE_NAME_FILE"
    echo "==> Staged text artifact: $FINAL_PACKAGE_NAME_FILE"
fi

MAR_SOURCE_DIR="$REPO_ROOT/output/mar/$TARGET"
if [[ -d "$MAR_SOURCE_DIR" ]]; then
    MAR_ARTIFACT_DIR="$ARTIFACT_DIR/mar"
    mkdir -p "$MAR_ARTIFACT_DIR"

    while IFS= read -r -d '' MAR_FILE; do
        MAR_BASENAME="$(basename "$MAR_FILE")"
        case "$MAR_BASENAME" in
            update.xml)
                FINAL_MAR="$MAR_ARTIFACT_DIR/${ARTIFACT_PREFIX}.update.xml"
                ;;
            *)
                FINAL_MAR="$MAR_ARTIFACT_DIR/$MAR_BASENAME"
                ;;
        esac

        cp "$MAR_FILE" "$FINAL_MAR"
        echo "==> Staged MAR artifact: $FINAL_MAR"
    done < <(find "$MAR_SOURCE_DIR" -maxdepth 1 -type f \( -name '*.mar' -o -name '*.xml' \) -print0)
fi
