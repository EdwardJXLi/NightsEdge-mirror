#!/usr/bin/env bash
set -euo pipefail

# Windmill cron script: checks mozilla-release for a new stable release tag.
# If found, updates FIREFOX_VERSION and pushes to Forgejo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$REPO_ROOT/FIREFOX_VERSION"

# --- Read current pinned version ---
source "$VERSION_FILE"
CURRENT_TAG="$RELEASE_TAG"
echo "==> Current pinned version: $CURRENT_TAG ($VERSION)"

# --- Query mozilla-release for latest release tag ---
echo "==> Checking mozilla-release for new release tags..."

LATEST_TAG=$(hg log -r "max(ancestors(tip) and tag('re:^FIREFOX_[0-9]+_[0-9]+_RELEASE$'))" \
    --template '{latesttag}\n' \
    https://hg.mozilla.org/releases/mozilla-release 2>/dev/null || true)

if [[ -z "$LATEST_TAG" ]]; then
    # Fallback: query tags endpoint
    LATEST_TAG=$(hg tags -R https://hg.mozilla.org/releases/mozilla-release 2>/dev/null \
        | grep -oP 'FIREFOX_[0-9]+_[0-9]+_RELEASE' \
        | head -1 || true)
fi

if [[ -z "$LATEST_TAG" ]]; then
    echo "Error: could not determine latest release tag"
    exit 1
fi

echo "==> Latest upstream tag: $LATEST_TAG"

# --- Compare ---
if [[ "$LATEST_TAG" == "$CURRENT_TAG" ]]; then
    echo "==> Already up to date. Nothing to do."
    exit 0
fi

echo "==> New release detected: $LATEST_TAG (was: $CURRENT_TAG)"

# --- Get commit hash for the new tag ---
NEW_HASH=$(hg log -r "tag('$LATEST_TAG')" \
    --template '{node|short}\n' \
    https://hg.mozilla.org/releases/mozilla-release 2>/dev/null)

if [[ -z "$NEW_HASH" ]]; then
    echo "Error: could not resolve commit hash for $LATEST_TAG"
    exit 1
fi

# --- Derive version number from tag (FIREFOX_128_0_RELEASE -> 128.0) ---
NEW_VERSION=$(echo "$LATEST_TAG" | sed -E 's/FIREFOX_([0-9]+)_([0-9]+)_RELEASE/\1.\2/')

echo "==> New version: $NEW_VERSION"
echo "==> New commit:  $NEW_HASH"

# --- Update FIREFOX_VERSION ---
cat > "$VERSION_FILE" <<EOF
# Firefox version pin — do not edit manually
COMMIT_HASH=$NEW_HASH
VERSION=$NEW_VERSION
RELEASE_TAG=$LATEST_TAG
EOF

# --- Commit and push ---
cd "$REPO_ROOT"
git add FIREFOX_VERSION
git commit -m "Update Firefox to ${NEW_VERSION} (${LATEST_TAG})"
git push origin main

echo "==> Pushed updated FIREFOX_VERSION. CI will pick up the build."
