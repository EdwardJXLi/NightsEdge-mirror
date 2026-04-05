#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="${SOURCE_DIR:-$REPO_ROOT/mozilla-release}"
WINSYSROOT_DIR="${1:-${WINSYSROOT_DIR:-/opt/winsysroot}}"
ENV_FILE="${2:-${WINDOWS_SYSROOT_ENV_FILE:-$WINSYSROOT_DIR/windows-env.sh}}"
VS_MANIFEST="${VS_MANIFEST:-}"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: SOURCE_DIR does not exist: $SOURCE_DIR"
    exit 1
fi

if [[ ! -x "$SOURCE_DIR/mach" ]]; then
    echo "Error: missing Mozilla mach runner at $SOURCE_DIR/mach"
    exit 1
fi

if [[ ! -f "$SOURCE_DIR/taskcluster/scripts/misc/get_vs.py" ]]; then
    echo "Error: missing Mozilla VS downloader at $SOURCE_DIR/taskcluster/scripts/misc/get_vs.py"
    exit 1
fi

if [[ -z "$VS_MANIFEST" ]]; then
    while IFS= read -r manifest; do
        VS_MANIFEST="$manifest"
        break
    done < <(find "$SOURCE_DIR/build/vs" -maxdepth 1 -type f -name 'vs*.yaml' \
        ! -name '*-aarch64.yaml' ! -name '*-car.yaml' | sort -V -r)
fi

if [[ -z "$VS_MANIFEST" || ! -f "$VS_MANIFEST" ]]; then
    echo "Error: missing Mozilla VS manifest YAML under $SOURCE_DIR/build/vs"
    exit 1
fi

echo "==> Downloading Windows SDK/MSVC sysroot into $WINSYSROOT_DIR"
echo "    Manifest: $VS_MANIFEST"
rm -rf "$WINSYSROOT_DIR"
mkdir -p "$WINSYSROOT_DIR"

(
    cd "$SOURCE_DIR"
    ./mach python --virtualenv build taskcluster/scripts/misc/get_vs.py -- "$VS_MANIFEST" "$WINSYSROOT_DIR"
)

WINDOWSSDKDIR="$WINSYSROOT_DIR/Windows Kits/10"
DIA_SDK_PATH="$WINSYSROOT_DIR/DIA SDK"

if [[ ! -d "$WINDOWSSDKDIR" || ! -d "$DIA_SDK_PATH" ]]; then
    echo "Error: downloaded toolchain is missing Windows SDK or DIA SDK"
    echo "       WINDOWSSDKDIR=$WINDOWSSDKDIR"
    echo "       DIA_SDK_PATH=$DIA_SDK_PATH"
    exit 1
fi

mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" <<EOF
export WINSYSROOT="$WINSYSROOT_DIR"
EOF

echo "==> Windows sysroot ready"
echo "    WINSYSROOT=$WINSYSROOT_DIR"
echo "    WINDOWSSDKDIR=$WINDOWSSDKDIR"
echo "    DIA_SDK_PATH=$DIA_SDK_PATH"
echo "    Env file: $ENV_FILE"
