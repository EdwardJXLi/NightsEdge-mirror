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

# Publish complete MARs at immutable paths. The update manifests are baked into
# the website image and reference these objects by Firefox build ID.
TARGETS=(
    linux-x86_64
    linux-aarch64
    windows-x86_64
    macos-x86_64
    macos-aarch64
)

for target in "${TARGETS[@]}"; do
    mar_dir="$ARTIFACTS_DIR/$target/mar"
    mar_file="$mar_dir/nightsedge-${VERSION}-${target}.complete.mar"
    update_xml="$mar_dir/nightsedge-${VERSION}-${target}.update.xml"

    if [[ ! -f "$mar_file" ]]; then
        echo "Error: release MAR not found: $mar_file" >&2
        exit 1
    fi
    if [[ ! -f "$update_xml" ]]; then
        echo "Error: update manifest not found: $update_xml" >&2
        exit 1
    fi

    build_id="$(
        sed -n 's/.*buildID="\([0-9][0-9]*\)".*/\1/p' "$update_xml" |
            head -1
    )"
    if [[ ! "$build_id" =~ ^[0-9]{14}$ ]]; then
        echo "Error: invalid or missing buildID in $update_xml" >&2
        exit 1
    fi

    mar_name="$(basename "$mar_file")"
    mar_url="https://nightsedge.hydranet.dev/mar/$build_id/$target/$mar_name"
    if ! grep -Fq "URL=\"$mar_url\"" "$update_xml"; then
        echo "Error: $update_xml does not reference $mar_url" >&2
        exit 1
    fi

    mc cp \
        "$mar_file" \
        "releases/$RELEASE_S3_BUCKET/mar/$build_id/$target/$mar_name"
    echo "==> Published immutable MAR for $target build $build_id"
done
