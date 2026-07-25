#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="${VERSION_FILE:-$REPO_ROOT/FIREFOX_VERSION}"
WEBSITE_TEMPLATE="${WEBSITE_TEMPLATE:-$REPO_ROOT/website/index.html.in}"
WEBSITE_OUTPUT="${WEBSITE_OUTPUT:-$REPO_ROOT/website/index.html}"
WEBSITE_UPDATES_DIR="${WEBSITE_UPDATES_DIR:-$REPO_ROOT/website/updates}"
PUBLIC_MAR_CERT="${PUBLIC_MAR_CERT:-$REPO_ROOT/certs/nightsedge-mar-primary.der}"
RELEASE_ARTIFACTS_DIR="${RELEASE_ARTIFACTS_DIR:-}"

source "$VERSION_FILE"
: "${VERSION:?VERSION must be set in FIREFOX_VERSION}"

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+)*([ab][0-9]+)?$ ]]; then
    echo "Error: unsupported Firefox version '$VERSION'" >&2
    exit 1
fi

if [[ ! -f "$PUBLIC_MAR_CERT" ]]; then
    echo "Error: MAR certificate not found: $PUBLIC_MAR_CERT" >&2
    exit 1
fi

resolve_release_hash() {
    local output_variable="$1"
    local target="$2"
    local filename="$3"
    local checksum_file
    local checksum_contents
    local checksum
    local recorded_filename

    if [[ -n "$RELEASE_ARTIFACTS_DIR" ]]; then
        checksum_file="${RELEASE_ARTIFACTS_DIR%/}/$target/$filename.sha256"
        if [[ ! -f "$checksum_file" ]]; then
            echo "Error: release checksum not found: $checksum_file" >&2
            exit 1
        fi
        echo "==> Reading $checksum_file"
        checksum_contents="$(<"$checksum_file")"
    else
        echo "==> Using a preview hash for $filename"
        checksum_contents="$(printf 'preview:%s' "$filename" | sha256sum)"
    fi

    read -r checksum recorded_filename _ <<< "$checksum_contents"
    checksum="${checksum,,}"
    if [[ ! "$checksum" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Error: invalid SHA-256 checksum for $filename" >&2
        exit 1
    fi
    if [[ -n "$RELEASE_ARTIFACTS_DIR" ]]; then
        recorded_filename="${recorded_filename#\*}"
        if [[ "$recorded_filename" != "$filename" ]]; then
            echo "Error: checksum sidecar does not name $filename" >&2
            exit 1
        fi
    fi

    printf -v "$output_variable" '%s' "$checksum"
}

resolve_release_hash \
    LINUX_X86_64_SHA256 \
    linux-x86_64 \
    "nightsedge-${VERSION}-linux-x86_64.tar.xz"
resolve_release_hash \
    LINUX_AARCH64_SHA256 \
    linux-aarch64 \
    "nightsedge-${VERSION}-linux-aarch64.tar.xz"
resolve_release_hash \
    WINDOWS_X86_64_INSTALLER_SHA256 \
    windows-x86_64 \
    "nightsedge-${VERSION}-windows-x86_64.installer.exe"
resolve_release_hash \
    WINDOWS_X86_64_ZIP_SHA256 \
    windows-x86_64 \
    "nightsedge-${VERSION}-windows-x86_64.zip"
resolve_release_hash \
    MACOS_AARCH64_SHA256 \
    macos-aarch64 \
    "nightsedge-${VERSION}-macos-aarch64.dmg"
resolve_release_hash \
    MACOS_X86_64_SHA256 \
    macos-x86_64 \
    "nightsedge-${VERSION}-macos-x86_64.dmg"

MAR_CERT_DIGEST="$(sha256sum "$PUBLIC_MAR_CERT" | cut -d' ' -f1)"
MAR_CERT_SHA256="$(
    printf '%s' "$MAR_CERT_DIGEST" |
        sed 's/../&:/g; s/:$//' |
        tr '[:lower:]' '[:upper:]'
)"

OUTPUT_DIR="$(dirname "$WEBSITE_OUTPUT")"
mkdir -p "$OUTPUT_DIR"
TEMP_OUTPUT="$(mktemp "$OUTPUT_DIR/.index.html.XXXXXX")"
TEMP_UPDATES_DIR=""

cleanup() {
    if [[ -n "$TEMP_OUTPUT" && -f "$TEMP_OUTPUT" ]]; then
        rm -f -- "$TEMP_OUTPUT"
    fi
    if [[ -n "$TEMP_UPDATES_DIR" && -d "$TEMP_UPDATES_DIR" ]]; then
        rm -rf -- "$TEMP_UPDATES_DIR"
    fi
}
trap cleanup EXIT

TEMPLATE_CONTENTS="$(<"$WEBSITE_TEMPLATE")"
TEMPLATE_CONTENTS="${TEMPLATE_CONTENTS//@VERSION@/$VERSION}"
TEMPLATE_CONTENTS="${TEMPLATE_CONTENTS//@LINUX_X86_64_SHA256@/$LINUX_X86_64_SHA256}"
TEMPLATE_CONTENTS="${TEMPLATE_CONTENTS//@LINUX_AARCH64_SHA256@/$LINUX_AARCH64_SHA256}"
TEMPLATE_CONTENTS="${TEMPLATE_CONTENTS//@WINDOWS_X86_64_INSTALLER_SHA256@/$WINDOWS_X86_64_INSTALLER_SHA256}"
TEMPLATE_CONTENTS="${TEMPLATE_CONTENTS//@WINDOWS_X86_64_ZIP_SHA256@/$WINDOWS_X86_64_ZIP_SHA256}"
TEMPLATE_CONTENTS="${TEMPLATE_CONTENTS//@MACOS_AARCH64_SHA256@/$MACOS_AARCH64_SHA256}"
TEMPLATE_CONTENTS="${TEMPLATE_CONTENTS//@MACOS_X86_64_SHA256@/$MACOS_X86_64_SHA256}"
TEMPLATE_CONTENTS="${TEMPLATE_CONTENTS//@MAR_CERT_SHA256@/$MAR_CERT_SHA256}"
printf '%s\n' "$TEMPLATE_CONTENTS" > "$TEMP_OUTPUT"

if grep -Eq '@[A-Z0-9_]+@' "$TEMP_OUTPUT"; then
    echo "Error: unresolved placeholder in rendered homepage" >&2
    exit 1
fi

chmod 0644 "$TEMP_OUTPUT"
mv "$TEMP_OUTPUT" "$WEBSITE_OUTPUT"
TEMP_OUTPUT=""

TEMP_UPDATES_DIR="$(mktemp -d "$OUTPUT_DIR/.updates.XXXXXX")"
chmod 0755 "$TEMP_UPDATES_DIR"
if [[ -n "$RELEASE_ARTIFACTS_DIR" ]]; then
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
        update_xml="${RELEASE_ARTIFACTS_DIR%/}/$target/mar/nightsedge-${VERSION}-${target}.update.xml"

        if [[ ! -f "$update_xml" ]]; then
            echo "Error: update manifest not found: $update_xml" >&2
            exit 1
        fi
        if ! grep -Eq \
            "URL=\"[^\"]*/mar/[0-9]{14}/$target/nightsedge-${VERSION}-${target}[.]complete[.]mar\"" \
            "$update_xml"; then
            echo "Error: update manifest does not reference an immutable MAR: $update_xml" >&2
            exit 1
        fi

        cp "$update_xml" "$TEMP_UPDATES_DIR/$build_target.xml"
        chmod 0644 "$TEMP_UPDATES_DIR/$build_target.xml"
        echo "==> Staged update manifest for $build_target"
    done
else
    echo "==> No release artifacts supplied; rendered image will not contain update manifests"
fi

if [[ -z "$WEBSITE_UPDATES_DIR" || "$WEBSITE_UPDATES_DIR" == "/" ]]; then
    echo "Error: refusing unsafe website updates directory: $WEBSITE_UPDATES_DIR" >&2
    exit 1
fi
rm -rf -- "$WEBSITE_UPDATES_DIR"
mv "$TEMP_UPDATES_DIR" "$WEBSITE_UPDATES_DIR"
TEMP_UPDATES_DIR=""
trap - EXIT

echo "==> Rendered homepage for NightsEdge $VERSION"
