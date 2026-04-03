#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/nightsedge"
BIN_LINK="/usr/local/bin/nightsedge"
BIN_LINK2="/usr/local/bin/firefox"
DESKTOP_FILE="/usr/share/applications/nightsedge.desktop"

if [[ $EUID -ne 0 ]]; then
    echo "Error: must run as root (try: sudo $0)"
    exit 1
fi

if [[ -d "$INSTALL_DIR" ]]; then
    echo "==> Removing install directory $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
else
    echo "==> Install directory not present: $INSTALL_DIR"
fi

if [[ -L "$BIN_LINK" || -e "$BIN_LINK" ]]; then
    echo "==> Removing launcher $BIN_LINK"
    rm -f "$BIN_LINK"
else
    echo "==> Launcher not present: $BIN_LINK"
fi

if [[ -L "$BIN_LINK2" || -e "$BIN_LINK2" ]]; then
    echo "==> Removing launcher $BIN_LINK2"
    rm -f "$BIN_LINK2"
else
    echo "==> Launcher not present: $BIN_LINK2"
fi

if [[ -f "$DESKTOP_FILE" ]]; then
    echo "==> Removing desktop entry $DESKTOP_FILE"
    rm -f "$DESKTOP_FILE"
else
    echo "==> Desktop entry not present: $DESKTOP_FILE"
fi

echo "==> Updating desktop database"
update-desktop-database /usr/share/applications 2>/dev/null || true

echo "==> NightsEdge removed."
