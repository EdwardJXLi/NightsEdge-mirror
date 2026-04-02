#!/usr/bin/env bash
set -euo pipefail

# Windmill cron script: checks upstream Firefox release metadata.
# If found, updates FIREFOX_VERSION and pushes to Forgejo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$REPO_ROOT/FIREFOX_VERSION"

# --- Read current pinned version ---
source "$VERSION_FILE"
UPSTREAM_REPO="${UPSTREAM_REPO:-mozilla-release}"
CURRENT_TRACK="${FIREFOX_TRACK:-}"
CURRENT_TAG="${RELEASE_TAG:-}"

if [[ -z "$CURRENT_TRACK" ]]; then
    case "$UPSTREAM_REPO" in
        mozilla-release) CURRENT_TRACK="release" ;;
        mozilla-beta) CURRENT_TRACK="beta" ;;
        mozilla-central) CURRENT_TRACK="nightly" ;;
        *)
            echo "Error: unsupported UPSTREAM_REPO '$UPSTREAM_REPO'"
            exit 1
            ;;
    esac
fi

case "$UPSTREAM_REPO" in
    mozilla-central)
        REPO_URL="https://hg.mozilla.org/mozilla-central"
        ;;
    mozilla-release|mozilla-beta)
        REPO_URL="https://hg.mozilla.org/releases/${UPSTREAM_REPO}"
        ;;
    *)
        echo "Error: unsupported UPSTREAM_REPO '$UPSTREAM_REPO'"
        exit 1
        ;;
esac

echo "==> Current pinned version: $VERSION"
echo "    Track: $CURRENT_TRACK"
echo "    Repo:  $UPSTREAM_REPO"
if [[ -n "$CURRENT_TAG" ]]; then
    echo "    Tag:   $CURRENT_TAG"
fi

case "$CURRENT_TRACK" in
    release)
        echo "==> Checking ${UPSTREAM_REPO} for new release tags..."

        LATEST_TAG=$(hg log -R "$REPO_URL" -r "max(ancestors(tip) and tag('re:^FIREFOX_[0-9]+_[0-9]+(_[0-9]+)?_RELEASE$'))" \
            --template '{latesttag}\n' \
            2>/dev/null || true)

        if [[ -z "$LATEST_TAG" ]]; then
            LATEST_TAG=$(hg tags -R "$REPO_URL" 2>/dev/null \
                | grep -oE 'FIREFOX_[0-9]+_[0-9]+(_[0-9]+)?_RELEASE' \
                | head -1 || true)
        fi

        if [[ -z "$LATEST_TAG" ]]; then
            echo "Error: could not determine latest release tag from $REPO_URL"
            exit 1
        fi

        echo "==> Latest upstream tag: $LATEST_TAG"

        if [[ "$LATEST_TAG" == "$CURRENT_TAG" ]]; then
            echo "==> Already up to date. Nothing to do."
            exit 0
        fi

        NEW_HASH=$(hg log -R "$REPO_URL" -r "tag('$LATEST_TAG')" \
            --template '{node|short}\n' \
            2>/dev/null)

        if [[ -z "$NEW_HASH" ]]; then
            echo "Error: could not resolve commit hash for $LATEST_TAG"
            exit 1
        fi

        NEW_VERSION=$(echo "$LATEST_TAG" | sed -E 's/^FIREFOX_([0-9]+)_([0-9]+)_([0-9]+)_RELEASE$/\1.\2.\3/; s/^FIREFOX_([0-9]+)_([0-9]+)_RELEASE$/\1.\2/')

        if [[ "$NEW_VERSION" == "$LATEST_TAG" || -z "$NEW_VERSION" ]]; then
            echo "Error: failed to parse version from tag $LATEST_TAG"
            exit 1
        fi

        echo "==> New release detected: $LATEST_TAG"
        ;;
    beta)
        echo "==> Checking ${UPSTREAM_REPO} for new beta version..."

        NEW_VERSION=$(hg cat -R "$REPO_URL" -r tip browser/config/version.txt 2>/dev/null | tr -d '\r\n' || true)
        NEW_HASH=$(hg log -R "$REPO_URL" -r tip --template '{node|short}\n' 2>/dev/null || true)

        if [[ -z "$NEW_VERSION" || -z "$NEW_HASH" ]]; then
            echo "Error: could not determine latest beta version from $REPO_URL"
            exit 1
        fi

        if [[ "$NEW_VERSION" == "$VERSION" ]]; then
            echo "==> Already up to date. Nothing to do."
            exit 0
        fi

        LATEST_TAG=""
        echo "==> New beta detected: $NEW_VERSION"
        ;;
    nightly)
        echo "==> Checking ${UPSTREAM_REPO} for new nightly version..."

        NEW_VERSION=$(hg cat -R "$REPO_URL" -r tip browser/config/version.txt 2>/dev/null | tr -d '\r\n' || true)
        NEW_HASH=$(hg log -R "$REPO_URL" -r tip --template '{node|short}\n' 2>/dev/null || true)

        if [[ -z "$NEW_VERSION" || -z "$NEW_HASH" ]]; then
            echo "Error: could not determine latest nightly version from $REPO_URL"
            exit 1
        fi

        if [[ "$NEW_VERSION" == "$VERSION" && "$NEW_HASH" == "${HG_COMMIT_HASH:-}" ]]; then
            echo "==> Already up to date. Nothing to do."
            exit 0
        fi

        LATEST_TAG=""
        echo "==> New nightly detected: $NEW_VERSION"
        ;;
    *)
        echo "Error: unsupported FIREFOX_TRACK '$CURRENT_TRACK'"
        exit 1
        ;;
esac

echo "==> New version: $NEW_VERSION"
echo "==> New commit:  $NEW_HASH"

# --- Update FIREFOX_VERSION ---
cat > "$VERSION_FILE" <<EOF
# Firefox version pin — do not edit manually
HG_COMMIT_HASH=$NEW_HASH
VERSION=$NEW_VERSION
UPSTREAM_REPO=$UPSTREAM_REPO
FIREFOX_TRACK=$CURRENT_TRACK
EOF

if [[ -n "${LATEST_TAG:-}" ]]; then
cat >> "$VERSION_FILE" <<EOF
RELEASE_TAG=$LATEST_TAG
EOF
fi

# --- Commit and push ---
cd "$REPO_ROOT"
git add FIREFOX_VERSION
if [[ -n "${LATEST_TAG:-}" ]]; then
    git commit -m "Update Firefox to ${NEW_VERSION} (${LATEST_TAG})"
else
    git commit -m "Update Firefox ${CURRENT_TRACK} to ${NEW_VERSION}"
fi
git push origin main

echo "==> Pushed updated FIREFOX_VERSION. CI will pick up the build."
