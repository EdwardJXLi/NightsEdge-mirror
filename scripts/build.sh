#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Parse arguments ---
TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "Usage: build.sh <target>"
    echo "Targets: linux-x86_64, linux-aarch64, win-x86_64"
    exit 1
fi

MOZCONFIG="$REPO_ROOT/mozconfigs/${TARGET}.mozconfig"
if [[ ! -f "$MOZCONFIG" ]]; then
    echo "Error: mozconfig not found: $MOZCONFIG"
    exit 1
fi

# --- Read version pin ---
source "$REPO_ROOT/FIREFOX_VERSION"

SOURCE_DIR="${SOURCE_DIR:-$REPO_ROOT/mozilla-release}"
UPSTREAM_REPO="${UPSTREAM_REPO:-mozilla-release}"
FIREFOX_TRACK="${FIREFOX_TRACK:-release}"

echo "==> NightsEdge build: $TARGET"
echo "    Firefox $VERSION (hg:$HG_COMMIT_HASH)"
echo "    Track:   $FIREFOX_TRACK"
echo "    Repo:    $UPSTREAM_REPO"

# --- Step 1: Fetch source ---
echo "==> Fetching source..."
"$SCRIPT_DIR/fetch-source.sh"

# --- Step 2: Copy mozconfig ---
echo "==> Installing mozconfig for $TARGET..."
cp "$MOZCONFIG" "$SOURCE_DIR/.mozconfig"

# --- Step 3: Custom version string ---
echo "==> Setting version display to hydra-${VERSION}..."
echo "hydra-${VERSION}" > "$SOURCE_DIR/browser/config/version_display.txt"

# --- Step 4: Install custom prefs ---
echo "==> Installing custom preferences..."
PREFS_DIR="$SOURCE_DIR/browser/defaults/preferences"
mkdir -p "$PREFS_DIR"
cp "$REPO_ROOT/prefs/nightsedge.js" "$PREFS_DIR/nightsedge.js"

# --- Step 5: Install enterprise policies ---
echo "==> Installing enterprise policies..."
POLICIES_DIR="$SOURCE_DIR/browser/defaults/policies"
mkdir -p "$POLICIES_DIR"
cp "$REPO_ROOT/policies/policies.json" "$POLICIES_DIR/policies.json"

# --- Step 6: Build ---
echo "==> Bootstrapping Firefox toolchains..."
cd "$SOURCE_DIR"
export MOZCONFIG="$SOURCE_DIR/.mozconfig"
./mach --no-interactive bootstrap --application-choice=browser

# Rustup installs into ~/.cargo/bin, which may not already be on PATH in CI.
if [[ -d "$HOME/.cargo/bin" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

if [[ "$TARGET" == "linux-aarch64" ]]; then
    echo "==> Installing Rust target aarch64-unknown-linux-gnu..."
    rustup target add aarch64-unknown-linux-gnu
fi

# Ubuntu commonly installs versioned llvm-objdump binaries without an
# unversioned PATH entry. Point mach at one if needed.
if ! command -v llvm-objdump >/dev/null 2>&1; then
    for candidate in /usr/bin/llvm-objdump-*; do
        if [[ -x "$candidate" ]]; then
            export LLVM_OBJDUMP="$candidate"
            echo "==> Using LLVM_OBJDUMP=$LLVM_OBJDUMP"
            break
        fi
    done
fi

echo "==> Starting build..."
./mach build

# --- Step 7: Package ---
echo "==> Packaging..."
./mach package

echo "==> Build complete for $TARGET"
echo "    Artifacts in: $SOURCE_DIR/obj-*/dist/"
