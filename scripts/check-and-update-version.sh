#!/usr/bin/env bash
set -euo pipefail

# Windmill cron script: checks upstream Firefox release metadata.
# If found, updates FIREFOX_VERSION and pushes to Forgejo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$REPO_ROOT/FIREFOX_VERSION"

AUTO_WRITE=false
AUTO_COMMIT=false
AUTO_PUSH=false

usage() {
    cat <<'EOF'
Usage: check-and-update-version.sh [--write] [--commit] [--push]

Checks upstream Firefox metadata for a new version.

Flags:
  --write   Update FIREFOX_VERSION when a new version is found
  --commit  Commit the updated FIREFOX_VERSION (implies --write)
  --push    Push the update commit to origin main (implies --commit)
  -h, --help  Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --write)
            AUTO_WRITE=true
            ;;
        --commit)
            AUTO_WRITE=true
            AUTO_COMMIT=true
            ;;
        --push)
            AUTO_WRITE=true
            AUTO_COMMIT=true
            AUTO_PUSH=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$1'"
            usage
            exit 1
            ;;
    esac
    shift
done

# --- Read current pinned version ---
source "$VERSION_FILE"
UPSTREAM_REPO="${UPSTREAM_REPO:-mozilla-release}"
CURRENT_TRACK="${FIREFOX_TRACK:-}"
CURRENT_TAG="${RELEASE_TAG:-}"

expected_track_from_repo() {
    case "$1" in
        mozilla-release) printf '%s\n' "release" ;;
        mozilla-beta) printf '%s\n' "beta" ;;
        mozilla-central) printf '%s\n' "nightly" ;;
        *)
            return 1
            ;;
    esac
}

EXPECTED_TRACK="$(expected_track_from_repo "$UPSTREAM_REPO" || true)"
if [[ -z "$EXPECTED_TRACK" ]]; then
    echo "Error: unsupported UPSTREAM_REPO '$UPSTREAM_REPO'"
    exit 1
fi

if [[ -z "$CURRENT_TRACK" ]]; then
    CURRENT_TRACK="$EXPECTED_TRACK"
elif [[ "$CURRENT_TRACK" != "$EXPECTED_TRACK" ]]; then
    echo "==> Warning: FIREFOX_TRACK=$CURRENT_TRACK does not match UPSTREAM_REPO=$UPSTREAM_REPO"
    echo "    Using derived track: $EXPECTED_TRACK"
    CURRENT_TRACK="$EXPECTED_TRACK"
fi

if [[ "$CURRENT_TRACK" != "release" && -n "$CURRENT_TAG" ]]; then
    echo "==> Warning: ignoring stale RELEASE_TAG for non-release track"
    CURRENT_TAG=""
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

fetch_latest_release_from_raw_tags() {
    local raw_tags
    local latest_entry

    raw_tags=$(curl -fsSL "$REPO_URL/raw-tags" 2>/dev/null || true)
    if [[ -z "$raw_tags" ]]; then
        return 1
    fi

    latest_entry=$(
        printf '%s\n' "$raw_tags" \
            | awk '
                /^[[:space:]]*FIREFOX_[0-9]+_[0-9]+(_[0-9]+)?_RELEASE[[:space:]]+[0-9a-f]+[[:space:]]*$/ {
                    tag = $1
                    hash = $2
                    version = tag
                    sub(/^FIREFOX_/, "", version)
                    sub(/_RELEASE$/, "", version)
                    gsub(/_/, ".", version)
                    printf "%s\t%s\t%s\n", version, tag, hash
                }
            ' \
            | sort -t $'\t' -k1,1V \
            | tail -n 1
    )

    if [[ -z "$latest_entry" ]]; then
        return 1
    fi

    LATEST_TAG=$(printf '%s\n' "$latest_entry" | cut -f2)
    NEW_HASH=$(printf '%s\n' "$latest_entry" | cut -f3)
    return 0
}

fetch_tip_version_and_hash() {
    local version_path="$1"
    local version_url="$REPO_URL/raw-file/tip/$version_path"
    local log_url="$REPO_URL/json-log?rev=tip"
    local log_json

    NEW_VERSION=$(curl -fsSL "$version_url" 2>/dev/null | tr -d '\r\n' || true)
    log_json=$(curl -fsSL "$log_url" 2>/dev/null || true)
    NEW_HASH=$(
        printf '%s' "$log_json" \
            | python3 -c 'import json, sys; data = json.load(sys.stdin); print(data["node"][:12])' 2>/dev/null \
            || true
    )

    if [[ -z "$NEW_VERSION" || -z "$NEW_HASH" ]]; then
        return 1
    fi

    return 0
}

case "$CURRENT_TRACK" in
    release)
        echo "==> Checking ${UPSTREAM_REPO} for new release tags..."

        LATEST_TAG=""
        NEW_HASH=""
        if ! fetch_latest_release_from_raw_tags; then
            echo "Error: could not determine latest release tag from $REPO_URL"
            exit 1
        fi

        echo "==> Latest upstream tag: $LATEST_TAG"

        if [[ "$LATEST_TAG" == "$CURRENT_TAG" ]]; then
            echo "==> Already up to date. Nothing to do."
            exit 0
        fi

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

        if ! fetch_tip_version_and_hash "browser/config/version_display.txt"; then
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

        if ! fetch_tip_version_and_hash "browser/config/version_display.txt"; then
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

if [[ "$AUTO_WRITE" != true ]]; then
    echo "==> Update available. Re-run with --write to update FIREFOX_VERSION."
    exit 0
fi

echo "==> Writing updated FIREFOX_VERSION..."

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

if [[ "$AUTO_COMMIT" != true ]]; then
    echo "==> Wrote FIREFOX_VERSION. Re-run with --commit to create a git commit."
    exit 0
fi

# --- Commit and push ---
cd "$REPO_ROOT"
git add FIREFOX_VERSION
if [[ -n "${LATEST_TAG:-}" ]]; then
    git commit -m "Update Firefox to ${NEW_VERSION} (${LATEST_TAG})"
else
    git commit -m "Update Firefox ${CURRENT_TRACK} to ${NEW_VERSION}"
fi

if [[ "$AUTO_PUSH" != true ]]; then
    echo "==> Created update commit. Re-run with --push to push it to origin main."
    exit 0
fi

git push origin main

echo "==> Pushed updated FIREFOX_VERSION. CI will pick up the build."
