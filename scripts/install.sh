#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

INSTALL_DIR="/opt/nightsedge"
BIN_LINK="/usr/local/bin/firefox"
BIN_LINK2="/usr/local/bin/nightsedge"
DESKTOP_FILE="/usr/share/applications/nightsedge.desktop"

# --- Find tarball ---
TARBALL="${1:-}"
if [[ -z "$TARBALL" ]]; then
    # Auto-detect from build output in the default source tree.
    TARBALL=$(find "$REPO_ROOT"/mozilla-release/obj-*/dist \( -name "*.tar.xz" -o -name "*.tar.bz2" \) 2>/dev/null | head -1)
fi

if [[ -z "$TARBALL" || ! -f "$TARBALL" ]]; then
    echo "Usage: install.sh [path-to-tarball]"
    echo "If no tarball is given, looks for build output in the default source tree at mozilla-release/obj-*/dist/"
    exit 1
fi

echo "==> Installing NightsEdge from $TARBALL"

# --- Need root ---
if [[ $EUID -ne 0 ]]; then
    echo "Error: must run as root (try: sudo $0 $*)"
    exit 1
fi

# --- Remove previous install ---
if [[ -d "$INSTALL_DIR" ]]; then
    echo "==> Removing previous install at $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
fi

# --- Extract ---
echo "==> Extracting to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
case "$TARBALL" in
    *.tar.xz)
        tar -xJf "$TARBALL" --strip-components=1 -C "$INSTALL_DIR"
        ;;
    *.tar.bz2)
        tar -xjf "$TARBALL" --strip-components=1 -C "$INSTALL_DIR"
        ;;
    *)
        echo "Error: unsupported tarball format: $TARBALL"
        exit 1
        ;;
esac

# --- Symlink ---
echo "==> Linking $BIN_LINK -> $INSTALL_DIR/firefox"
ln -sf "$INSTALL_DIR/firefox" "$BIN_LINK"
echo "==> Linking $BIN_LINK2 -> $INSTALL_DIR/firefox"
ln -sf "$INSTALL_DIR/firefox" "$BIN_LINK2"

# --- Desktop entry ---
echo "==> Installing desktop entry"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Firefox Nightly (NightsEdge)
GenericName=Web Browser
Comment=Custom Firefox build for Hydra
Exec=firefox %u
Icon=$INSTALL_DIR/browser/chrome/icons/default/default128.png
Terminal=false
Type=Application
MimeType=text/html;text/xml;application/xhtml+xml;application/vnd.mozilla.xul+xml;text/mml;x-scheme-handler/http;x-scheme-handler/https;
Categories=Network;WebBrowser;
StartupNotify=true
StartupWMClass=Firefox Nightly (NightsEdge)
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=Open a New Window
Exec=firefox --new-window %u

[Desktop Action new-private-window]
Name=Open a New Private Window
Exec=firefox --private-window %u
EOF

echo "==> Updating desktop database"
update-desktop-database /usr/share/applications 2>/dev/null || true

echo "==> Done. Run 'firefox' to launch."
