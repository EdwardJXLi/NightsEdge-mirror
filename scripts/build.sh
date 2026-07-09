#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Parse arguments ---
TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "Usage: build.sh <target>"
    echo "Targets: linux-x86_64, linux-aarch64, windows-x86_64"
    exit 1
fi

# Extra Rust std target needed on top of the host toolchain, if any.
RUST_TARGET=""
case "$TARGET" in
    linux-x86_64) ;;
    linux-aarch64)  RUST_TARGET="aarch64-unknown-linux-gnu" ;;
    windows-x86_64) RUST_TARGET="x86_64-pc-windows-msvc" ;;
    *)
        echo "Error: unsupported target '$TARGET'"
        exit 1
        ;;
esac

# get_vs.py extracts the Microsoft SDK/MSVC payloads with msiextract.
if [[ "$TARGET" == "windows-x86_64" ]] && ! command -v msiextract >/dev/null 2>&1; then
    echo "Error: msiextract not found; it is required to unpack the Windows SDK." >&2
    echo "       Install the 'msitools' package." >&2
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

if [[ -z "${RUST_VERSION:-}" ]]; then
    echo "Error: RUST_VERSION is not set in FIREFOX_VERSION." >&2
    echo "       Re-run scripts/check-and-update-version.sh --write to populate it." >&2
    exit 1
fi

echo "==> NightsEdge build: $TARGET"
echo "    Firefox $VERSION (hg:$HG_COMMIT_HASH)"
echo "    Track:   $FIREFOX_TRACK"
echo "    Repo:    $UPSTREAM_REPO"
echo "    Rust:    $RUST_VERSION"

# --- Step 1: Fetch source (skip if already present) ---
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    echo "==> Fetching source..."
    "$SCRIPT_DIR/fetch-source.sh"
else
    echo "==> Source already present at $SOURCE_DIR, skipping fetch."
fi

# --- Step 2: Apply source patches ---
echo "==> Applying source patches..."
for patch in "$REPO_ROOT"/patches/*.patch; do
    [[ -e "$patch" ]] || continue
    if git -C "$SOURCE_DIR" apply --reverse --check "$patch" 2>/dev/null; then
        echo "    Skipping $(basename "$patch") (already applied)"
    else
        echo "    Applying $(basename "$patch")"
        git -C "$SOURCE_DIR" apply "$patch"
    fi
done

# --- Step 3: Copy mozconfig ---
echo "==> Installing mozconfig for $TARGET..."
cp "$MOZCONFIG" "$SOURCE_DIR/.mozconfig"

# --- Step 4: Custom version string ---
echo "==> Setting version display to hydra-${VERSION}..."
echo "hydra-${VERSION}" > "$SOURCE_DIR/browser/config/version_display.txt"

# --- Step 5: Install custom prefs ---
echo "==> Installing custom preferences..."
PREFS_DIR="$SOURCE_DIR/browser/defaults/preferences"
mkdir -p "$PREFS_DIR"
cp "$REPO_ROOT/prefs/nightsedge.js" "$PREFS_DIR/nightsedge.js"

# --- Step 6: Install enterprise policies ---
echo "==> Installing enterprise policies..."
POLICIES_DIR="$SOURCE_DIR/browser/defaults/policies"
mkdir -p "$POLICIES_DIR"
cp "$REPO_ROOT/policies/policies.json" "$POLICIES_DIR/policies.json"

# --- Step 7: Build ---
echo "==> Bootstrapping Firefox toolchains..."
cd "$SOURCE_DIR"
export MOZCONFIG="$SOURCE_DIR/.mozconfig"
./mach --no-interactive bootstrap --application-choice=browser

# Rustup installs into ~/.cargo/bin, which may not already be on PATH in CI.
if [[ -d "$HOME/.cargo/bin" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Pin Rust to the version Firefox was tested against; rolling "stable" breaks the build
echo "==> Pinning Rust toolchain to $RUST_VERSION..."
rustup toolchain install "$RUST_VERSION" --profile minimal --no-self-update
export RUSTUP_TOOLCHAIN="$RUST_VERSION"
rustc --version

SCCACHE_ENABLED=0
if [[ "${SCCACHE_DISABLE:-0}" != "1" ]] && command -v sccache >/dev/null 2>&1; then
    export SCCACHE_BIN="${SCCACHE_BIN:-$(command -v sccache)}"
    export RUSTC_WRAPPER="${RUSTC_WRAPPER:-$SCCACHE_BIN}"
    export SCCACHE_IDLE_TIMEOUT="${SCCACHE_IDLE_TIMEOUT:-0}"
    SCCACHE_ENABLED=1

    echo "==> Enabling sccache via $SCCACHE_BIN"
    if [[ -n "${SCCACHE_BUCKET:-}" && -n "${SCCACHE_ENDPOINT:-}" ]]; then
        echo "    Backend: S3"
        echo "    Bucket:  $SCCACHE_BUCKET"
        echo "    Endpoint: $SCCACHE_ENDPOINT"
    else
        echo "    Backend: local/default (S3 backend not fully configured)"
    fi

    # Restart so the server picks up the current S3 credentials
    "$SCCACHE_BIN" --stop-server >/dev/null 2>&1 || true
    "$SCCACHE_BIN" --start-server

    # Verify the reported storage backend
    SCCACHE_STORAGE=$("$SCCACHE_BIN" --show-stats 2>&1 | grep -i "cache location" || true)
    echo "    Storage: $SCCACHE_STORAGE"
    if [[ -n "${SCCACHE_BUCKET:-}" ]] && ! echo "$SCCACHE_STORAGE" | grep -qi "s3"; then
        echo "WARNING: sccache S3 backend was configured but storage reports: $SCCACHE_STORAGE"
        echo "         Cache writes may not persist. Check credentials and endpoint."
    fi
else
    echo "==> sccache not enabled (install sccache or unset SCCACHE_DISABLE=1)"
fi

if [[ -n "$RUST_TARGET" ]]; then
    echo "==> Installing Rust target $RUST_TARGET for $RUST_VERSION..."
    rustup target add --toolchain "$RUST_VERSION" "$RUST_TARGET"
fi

# Ubuntu often ships only versioned llvm-objdump binaries
if ! command -v llvm-objdump >/dev/null 2>&1; then
    for candidate in /usr/bin/llvm-objdump-*; do
        if [[ -x "$candidate" ]]; then
            export LLVM_OBJDUMP="$candidate"
            echo "==> Using LLVM_OBJDUMP=$LLVM_OBJDUMP"
            break
        fi
    done
fi

if [[ "$TARGET" == "windows-x86_64" ]]; then
    # configure checks MIDL (wine's widl) before bootstrap would fetch wine
    if [[ ! -x "$HOME/.mozbuild/wine/bin/widl" ]]; then
        echo "==> Fetching Mozilla wine toolchain (provides widl)..."
        mkdir -p "$HOME/.mozbuild"
        (cd "$HOME/.mozbuild" && python3 "$SOURCE_DIR/mach" artifact toolchain --from-build linux64-wine)
    fi
fi

echo "==> Starting build..."
./mach build

# --- Step 8: Package ---
echo "==> Packaging..."
./mach package

# The NSIS installer is a separate target from `mach package`; bootstrap
# already provisions NSIS/7zz/UPX into ~/.mozbuild for this to run on Linux.
if [[ "$TARGET" == "windows-x86_64" ]]; then
    echo "==> Building NSIS installer..."
    ./mach build installer
fi

if [[ "$SCCACHE_ENABLED" == "1" ]]; then
    echo "==> sccache stats"
    "$SCCACHE_BIN" --show-stats || true
    echo "==> Stopping sccache server (flushing pending uploads)..."
    "$SCCACHE_BIN" --stop-server || true
fi

echo "==> Build complete for $TARGET"
echo "    Artifacts in: $SOURCE_DIR/obj-*/dist/"
