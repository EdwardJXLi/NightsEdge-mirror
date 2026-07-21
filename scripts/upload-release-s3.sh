#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$REPO_ROOT/artifacts}"

: "${RELEASE_S3_ENDPOINT:?RELEASE_S3_ENDPOINT must be set}"
: "${RELEASE_S3_BUCKET:?RELEASE_S3_BUCKET must be set}"
: "${RELEASE_S3_ACCESS_KEY:?RELEASE_S3_ACCESS_KEY must be set}"
: "${RELEASE_S3_SECRET_KEY:?RELEASE_S3_SECRET_KEY must be set}"

if [[ -z "$(find "$ARTIFACTS_DIR" -type f 2>/dev/null)" ]]; then
    echo "==> No release artifacts found to upload, skipping"
    exit 0
fi

source "$REPO_ROOT/FIREFOX_VERSION"
: "${VERSION:?VERSION must be set in FIREFOX_VERSION}"

mc alias set releases "$RELEASE_S3_ENDPOINT" "$RELEASE_S3_ACCESS_KEY" "$RELEASE_S3_SECRET_KEY"

# Keep every release available for direct downloads.
mc mirror --overwrite "$ARTIFACTS_DIR" "releases/$RELEASE_S3_BUCKET/releases/$VERSION"
echo "==> Uploaded release artifacts to s3://$RELEASE_S3_BUCKET/releases/$VERSION/"

# Publish the latest complete MARs and update manifests at the stable paths
# compiled into Firefox. %BUILD_TARGET% expands to the XPCOM ABI values below.
TARGETS=(
    "linux-x86_64:Linux_x86_64-gcc3"
    "linux-aarch64:Linux_aarch64-gcc3"
    "windows-x86_64:WINNT_x86_64-msvc-x64"
    "macos-x86_64:Darwin_x86_64-gcc3"
    "macos-aarch64:Darwin_aarch64-gcc3"
)

for target_mapping in "${TARGETS[@]}"; do
    target="${target_mapping%%:*}"
    build_target="${target_mapping#*:}"
    mar_dir="$ARTIFACTS_DIR/$target/mar"

    [[ -d "$mar_dir" ]] || continue

    while IFS= read -r -d '' mar_file; do
        mar_name="$(basename "$mar_file")"
        mc cp "$mar_file" "releases/$RELEASE_S3_BUCKET/mar/$target/$mar_name"
    done < <(find "$mar_dir" -maxdepth 1 -type f -name '*.mar' -print0)

    update_xml="$(find "$mar_dir" -maxdepth 1 -type f -name '*.update.xml' -print -quit)"
    if [[ -n "$update_xml" ]]; then
        mc cp "$update_xml" "releases/$RELEASE_S3_BUCKET/updates/$build_target.xml"
        echo "==> Published update manifest for $build_target"
    fi
done
