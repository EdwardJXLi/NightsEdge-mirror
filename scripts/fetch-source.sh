#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="${SOURCE_DIR:-$REPO_ROOT/mozilla-release}"

GITHUB_REPO="https://github.com/mozilla-firefox/firefox.git"

# Read version pin
source "$REPO_ROOT/FIREFOX_VERSION"

echo "==> Fetching Firefox source"
echo "    Version: $VERSION"
echo "    Hg hash: $HG_COMMIT_HASH"

# Translate hg hash to git hash via Mozilla's JSON API
echo "==> Resolving git commit from hg hash..."
GIT_COMMIT_HASH=$(curl -sL "https://hg.mozilla.org/releases/mozilla-release/json-rev/$HG_COMMIT_HASH" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['git_commit'])")

if [[ -z "$GIT_COMMIT_HASH" ]]; then
    echo "ERROR: Failed to resolve git hash for hg commit $HG_COMMIT_HASH"
    exit 1
fi

echo "    Git hash: $GIT_COMMIT_HASH"

if [[ -d "$SOURCE_DIR" ]]; then
    echo "==> Source directory exists, updating..."
    cd "$SOURCE_DIR"
    git fetch --depth 1 origin "$GIT_COMMIT_HASH"
    git checkout "$GIT_COMMIT_HASH"
else
    echo "==> Shallow cloning at $GIT_COMMIT_HASH..."
    git init "$SOURCE_DIR"
    cd "$SOURCE_DIR"
    git remote add origin "$GITHUB_REPO"
    git fetch --depth 1 origin "$GIT_COMMIT_HASH"
    git checkout "$GIT_COMMIT_HASH"
fi

echo "==> Source ready at $SOURCE_DIR"
