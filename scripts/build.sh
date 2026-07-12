#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Parse arguments ---
TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "Usage: build.sh <target>"
    echo "Targets: linux-x86_64, linux-aarch64, windows-x86_64, macos-x86_64, macos-aarch64"
    exit 1
fi

# Extra Rust std target needed on top of the host toolchain, if any.
RUST_TARGET=""
case "$TARGET" in
    linux-x86_64) ;;
    linux-aarch64) RUST_TARGET="aarch64-unknown-linux-gnu" ;;
    windows-x86_64) RUST_TARGET="x86_64-pc-windows-msvc" ;;
    macos-x86_64)  RUST_TARGET="x86_64-apple-darwin" ;;
    macos-aarch64) RUST_TARGET="aarch64-apple-darwin" ;;
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
PREFS_DIR="$SOURCE_DIR/browser/app/profile"
mkdir -p "$PREFS_DIR"
# package-default-preferences.patch includes this source file at the end of
# firefox.js. Preferences owned by Nightly branding are patched separately.
rm -f "$PREFS_DIR/00-nightsedge.js"
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

# HACK: Apple purges old CLT pkgs and release tags keep pinning the dead url.
# Scrape the pin from the tree and retry through wayback when Apple 403s.
if [[ "$TARGET" == macos-* ]]; then
    read -r SDK_URL SDK_SHA512 SDK_PREFIX < <(
        python3 - "$SOURCE_DIR/taskcluster/kinds/toolchain/macos-sdk.yml" <<'EOF'
import re, sys

sdks = []
for m in re.finditer(r"^macosx64-sdk-([\d.]+):(?:\n[ \t].*)*", open(sys.argv[1]).read(), re.M):
    args = re.search(r"arguments:\n((?:[ \t]+- .+\n)+)", m.group(0))
    sdks.append(([int(x) for x in m.group(1).split(".")], re.findall(r"- (.+)", args.group(1))))
print(*max(sdks)[1][:3])
EOF
    )

    # The availability API is flaky and can return an archived 403 page; query
    # the CDX index for the newest status-200 capture and fail loud on a miss.
    wayback_url() {
        python3 -c 'import json, sys, urllib.parse, urllib.request
url = sys.argv[1]
api = ("https://web.archive.org/cdx/search/cdx?url="
       + urllib.parse.quote(url, safe="")
       + "&output=json&filter=statuscode:200&limit=-1")
rows = json.load(urllib.request.urlopen(api, timeout=60))
if len(rows) < 2:
    sys.exit("no archived status-200 snapshot for " + url)
print("https://web.archive.org/web/" + rows[1][1] + "id_/" + url)' "$1"
    }

    fetch_sdk() {
        rm -rf "$SDK_DIR.tmp"
        PYTHONPATH="$SOURCE_DIR/python/mozbuild" python3 \
            "$SOURCE_DIR/taskcluster/scripts/misc/unpack-sdk.py" \
            "$1" "$SDK_SHA512" "$SDK_PREFIX" "$SDK_DIR.tmp"
    }

    SDK_DIR="$HOME/.mozbuild/$(basename "$SDK_PREFIX")"
    if [[ ! -d "$SDK_DIR" ]]; then
        echo "==> Fetching $(basename "$SDK_PREFIX")..."
        if ! fetch_sdk "$SDK_URL"; then
            echo "    Apple returned an error; retrying via Wayback Machine..."
            WB_URL="$(wayback_url "$SDK_URL")"
            echo "    Wayback: $WB_URL"
            fetch_sdk "$WB_URL"
        fi
        mv "$SDK_DIR.tmp" "$SDK_DIR"
    fi
    export MACOS_SDK_DIR="$SDK_DIR"
    echo "==> Using macOS SDK: $MACOS_SDK_DIR"
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

# Apple Silicon kills Mach-Os whose linker ad-hoc signatures went stale during
# packaging; re-sign the staged .app and rebuild the DMG from it.
if [[ "$TARGET" == macos-* ]]; then
    RCODESIGN_VERSION="0.29.0"
    RCODESIGN="$HOME/.mozbuild/rcodesign-$RCODESIGN_VERSION/rcodesign"
    if [[ ! -x "$RCODESIGN" ]]; then
        echo "==> Fetching rcodesign $RCODESIGN_VERSION..."
        mkdir -p "$(dirname "$RCODESIGN")"
        curl -fsSL "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${RCODESIGN_VERSION}/apple-codesign-${RCODESIGN_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
            | tar -xz --strip-components=1 -C "$(dirname "$RCODESIGN")"
    fi

    case "$TARGET" in
        macos-x86_64)  OBJ_DIR="$SOURCE_DIR/obj-x86_64-apple-darwin" ;;
        macos-aarch64) OBJ_DIR="$SOURCE_DIR/obj-aarch64-apple-darwin" ;;
    esac
    STAGED_APP="$(find "$OBJ_DIR/dist" -mindepth 2 -maxdepth 2 -type d -name '*.app' | head -1)"
    if [[ -z "$STAGED_APP" ]]; then
        echo "Error: no staged .app found under $OBJ_DIR/dist" >&2
        exit 1
    fi

    echo "==> Ad-hoc signing $(basename "$STAGED_APP")..."
    "$RCODESIGN" sign "$STAGED_APP"

    echo "==> Rebuilding DMG from signed app..."
    APP_TAR="$OBJ_DIR/signed-app.tar.gz"
    tar -czf "$APP_TAR" -C "$(dirname "$STAGED_APP")" "$(basename "$STAGED_APP")"
    ./mach repackage dmg -i "$APP_TAR" -o "$OBJ_DIR/dist/$(cat "$OBJ_DIR/dist/package_name.txt")"
    rm -f "$APP_TAR"
fi

if [[ "$SCCACHE_ENABLED" == "1" ]]; then
    echo "==> sccache stats"
    "$SCCACHE_BIN" --show-stats || true
    echo "==> Stopping sccache server (flushing pending uploads)..."
    "$SCCACHE_BIN" --stop-server || true
fi

echo "==> Build complete for $TARGET"
echo "    Artifacts in: $SOURCE_DIR/obj-*/dist/"
