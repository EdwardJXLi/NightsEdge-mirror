#!/usr/bin/env bash
set -euo pipefail

MC_RELEASE="RELEASE.2025-08-13T08-35-41Z"
MC_SHA256="01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891"
MC_BINARY="mc.linux-amd64.$MC_RELEASE"
MC_URL="https://github.com/minio/mc/releases/download/$MC_RELEASE/$MC_BINARY"

MC_DOWNLOAD="$(mktemp)"
trap 'rm -f "$MC_DOWNLOAD"' EXIT

curl -fsSL --retry 3 -o "$MC_DOWNLOAD" "$MC_URL"
printf '%s  %s\n' "$MC_SHA256" "$MC_DOWNLOAD" | sha256sum -c -
install -m 0755 "$MC_DOWNLOAD" /usr/local/bin/mc
mc --version
