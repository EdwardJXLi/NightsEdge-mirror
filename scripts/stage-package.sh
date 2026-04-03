#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "Usage: stage-package.sh <target>"
    echo "Targets: linux-x86_64, linux-aarch64, windows-x86_64"
    exit 1
fi

source "$REPO_ROOT/FIREFOX_VERSION"

: "${VERSION:?VERSION must be set in FIREFOX_VERSION}"

case "$TARGET" in
    linux-x86_64)
        OBJ_PATTERN="obj-x86_64-pc-linux-gnu"
        ARTIFACT_DIR="$REPO_ROOT/artifacts/linux-x86_64"
        PACKAGE_GLOB_1="*.tar.xz"
        PACKAGE_GLOB_2="*.tar.bz2"
        FINAL_PACKAGE_SUFFIX="tar"
        ;;
    linux-aarch64)
        OBJ_PATTERN="obj-aarch64-unknown-linux-gnu"
        ARTIFACT_DIR="$REPO_ROOT/artifacts/linux-aarch64"
        PACKAGE_GLOB_1="*.tar.xz"
        PACKAGE_GLOB_2="*.tar.bz2"
        FINAL_PACKAGE_SUFFIX="tar"
        ;;
    windows-x86_64)
        OBJ_PATTERN="obj-x86_64-pc-windows-msvc"
        ARTIFACT_DIR="$REPO_ROOT/artifacts/windows-x86_64"
        PACKAGE_GLOB_1="*.zip"
        PACKAGE_GLOB_2=""
        FINAL_PACKAGE_SUFFIX="zip"
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

if [[ -n "$PACKAGE_GLOB_2" ]]; then
    PACKAGE="$(find "$OBJ_DIR/dist" -maxdepth 1 -type f \( -name "$PACKAGE_GLOB_1" -o -name "$PACKAGE_GLOB_2" \) | head -1)"
else
    PACKAGE="$(find "$OBJ_DIR/dist" -maxdepth 1 -type f -name "$PACKAGE_GLOB_1" | head -1)"
fi

if [[ -z "$PACKAGE" ]]; then
    echo "Error: no package archive found in $OBJ_DIR/dist"
    exit 1
fi

case "$PACKAGE" in
    *.tar.xz) EXT="xz" ;;
    *.tar.bz2) EXT="bz2" ;;
    *.zip) EXT="" ;;
    *)
        echo "Error: unsupported package format: $PACKAGE"
        exit 1
        ;;
esac

mkdir -p "$ARTIFACT_DIR"

if [[ "$FINAL_PACKAGE_SUFFIX" == "zip" ]]; then
    FINAL_PACKAGE="$ARTIFACT_DIR/${ARTIFACT_PREFIX}.zip"
else
    FINAL_PACKAGE="$ARTIFACT_DIR/${ARTIFACT_PREFIX}.${FINAL_PACKAGE_SUFFIX}.${EXT}"
fi

cp "$PACKAGE" "$FINAL_PACKAGE"
echo "==> Final package: $FINAL_PACKAGE"

PACKAGE_NAME_FILE="$OBJ_DIR/dist/package_name.txt"
if [[ -f "$PACKAGE_NAME_FILE" ]]; then
    FINAL_PACKAGE_NAME_FILE="$ARTIFACT_DIR/${ARTIFACT_PREFIX}.package_name.txt"
    cp "$PACKAGE_NAME_FILE" "$FINAL_PACKAGE_NAME_FILE"
    echo "==> Staged text artifact: $FINAL_PACKAGE_NAME_FILE"
fi

if [[ "$TARGET" == "windows-x86_64" ]]; then
    while IFS= read -r -d '' EXE_FILE; do
        EXE_BASENAME="$(basename "$EXE_FILE")"
        FINAL_EXE="$ARTIFACT_DIR/${ARTIFACT_PREFIX}.${EXE_BASENAME}"
        cp "$EXE_FILE" "$FINAL_EXE"
        echo "==> Staged Windows artifact: $FINAL_EXE"
    done < <(find "$OBJ_DIR/dist" -maxdepth 1 -type f -name '*.exe' -print0)
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
