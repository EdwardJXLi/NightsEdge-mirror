#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="${SOURCE_DIR:-$REPO_ROOT/mozilla-release}"

# Read version pin
source "$REPO_ROOT/FIREFOX_VERSION"

echo "==> Fetching Firefox source"
echo "    Version: $VERSION"
echo "    Tag:     $RELEASE_TAG"
echo "    Commit:  $COMMIT_HASH"

if [[ -d "$SOURCE_DIR" ]]; then
    echo "==> Source directory exists, updating..."
    cd "$SOURCE_DIR"
    hg pull
    hg update -r "$COMMIT_HASH"
else
    echo "==> Cloning mozilla-release at $COMMIT_HASH..."
    hg clone https://hg.mozilla.org/releases/mozilla-release -r "$COMMIT_HASH" "$SOURCE_DIR"
fi

echo "==> Source ready at $SOURCE_DIR"
