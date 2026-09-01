#!/usr/bin/env bash
# Install m720-config: adds `mouse modify` to the existing mouse service tooling.
# Does not touch mouse.service or your current /etc/logid.cfg.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB=/usr/local/lib/m720-config
BIN=/usr/local/bin

[[ $EUID -eq 0 ]] || { echo "run with sudo: sudo $0" >&2; exit 1; }

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

# Keep a copy of the wrapper we are replacing.
if [[ -f $BIN/mouse ]] && ! cmp -s "$BIN/mouse" "$SRC/bin/mouse"; then
    cp -a "$BIN/mouse" "$BIN/mouse.pre-m720-config"
    echo "saved previous wrapper -> $BIN/mouse.pre-m720-config"
fi

install -d -m 0755 "$LIB"
install -m 0755 "$SRC/bin/mouse"        "$BIN/mouse"
install -m 0755 "$SRC/bin/mouse-apply"  "$BIN/mouse-apply"
install -m 0755 "$SRC/lib/server.py"    "$LIB/server.py"
install -m 0644 "$SRC/lib/ui.html"      "$LIB/ui.html"

# The UI reads the live config as your user. logid runs as root and does not
# need it private, so make sure it is world-readable like a normal /etc file.
if [[ -f /etc/logid.cfg ]]; then
    chmod 0644 /etc/logid.cfg
fi

install -d -m 0755 /var/backups/m720-config

if ! command -v imwheel >/dev/null; then
    echo
    echo "note: imwheel is not installed. It is optional and only needed for the"
    echo "      scroll-speed setting (logiops cannot change scroll speed):"
    echo "        sudo apt install imwheel"
fi

echo
echo "Installed:"
echo "  $BIN/mouse            (now has: modify, logs, follow, edit, revert)"
echo "  $BIN/mouse-apply      (root helper: backup, install, restart, verify, roll back)"
echo "  $LIB/{server.py,ui.html}"
echo
echo "Run:  mouse modify"
