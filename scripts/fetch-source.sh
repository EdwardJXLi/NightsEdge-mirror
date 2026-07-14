#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="${SOURCE_DIR:-$REPO_ROOT/mozilla-release}"

GITHUB_REPO="https://github.com/mozilla-firefox/firefox.git"

# Read version pin
source "$REPO_ROOT/FIREFOX_VERSION"
UPSTREAM_REPO="${UPSTREAM_REPO:-mozilla-release}"

case "$UPSTREAM_REPO" in
    mozilla-central)
        REPO_URL="https://hg.mozilla.org/mozilla-central"
        ;;
    mozilla-release|mozilla-beta)
        REPO_URL="https://hg.mozilla.org/releases/${UPSTREAM_REPO}"
        ;;
    *)
        echo "ERROR: Unsupported UPSTREAM_REPO '$UPSTREAM_REPO'"
        exit 1
        ;;
esac

echo "==> Fetching Firefox source"
echo "    Version: $VERSION"
echo "    Hg hash: $HG_COMMIT_HASH"
echo "    Repo:    $UPSTREAM_REPO"

# Translate hg hash to git hash via Mozilla's JSON API
echo "==> Resolving git commit from hg hash..."
GIT_COMMIT_HASH=$(curl -sL "${REPO_URL}/json-rev/${HG_COMMIT_HASH}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['git_commit'])")

if [[ -z "$GIT_COMMIT_HASH" ]]; then
    echo "ERROR: Failed to resolve git hash for hg commit $HG_COMMIT_HASH"
    exit 1
fi

echo "    Git hash: $GIT_COMMIT_HASH"

if [[ -d "$SOURCE_DIR/.git" ]]; then
    echo "==> Source directory exists, updating..."
    cd "$SOURCE_DIR"
    git fetch --depth 1 origin "$GIT_COMMIT_HASH"
    git checkout --detach --force "$GIT_COMMIT_HASH"
elif [[ -e "$SOURCE_DIR" ]]; then
    echo "ERROR: Source path exists but is not a Git checkout: $SOURCE_DIR" >&2
    exit 1
else
    echo "==> Shallow cloning at $GIT_COMMIT_HASH..."
    git init "$SOURCE_DIR"
    cd "$SOURCE_DIR"
    git remote add origin "$GITHUB_REPO"
    git fetch --depth 1 origin "$GIT_COMMIT_HASH"
    git checkout --detach "$GIT_COMMIT_HASH"
fi

echo "==> Source ready at $SOURCE_DIR"
