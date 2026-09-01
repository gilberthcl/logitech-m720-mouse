#!/usr/bin/env bash
# Install the M720 remapper on macOS. Entirely user-level: no sudo, no
# /usr/local, no package manager, no system extension.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN="$HOME/.local/bin"
LIB="$HOME/.local/lib/m720-config"
CFG_DIR="$HOME/.config/m720-config"
CONFIG="$CFG_DIR/config.json"
LABEL=local.m720d
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/m720d.log"
TARGET="gui/$(id -u)/$LABEL"

[[ $EUID -ne 0 ]] || { echo "do NOT run this with sudo — it installs into your home" >&2; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found. Run: xcode-select --install" >&2; exit 1; }

mkdir -p "$BIN" "$LIB" "$CFG_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

echo "compiling m720d…"
swiftc -O -o "$BIN/m720d.new" "$SRC/src/m720d.swift" || {
    echo; echo "compile failed — nothing was installed or changed." >&2; exit 1; }
mv "$BIN/m720d.new" "$BIN/m720d"

install -m 0755 "$SRC/bin/mouse" "$BIN/mouse"

# The web UI is not installed yet on macOS: lib/server.py writes
# /etc/logid.cfg, which is meaningless here. Configure with `mouse edit`
# until the macOS backend for it lands.

if [[ ! -f $CONFIG ]]; then
    cp "$SRC/config.example.json" "$CONFIG"
    echo "wrote a starting config to $CONFIG"
else
    cp "$CONFIG" "$CONFIG.bak"
    echo "kept your existing config (backed up to $CONFIG.bak)"
fi

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>$LABEL</string>
  <key>ProgramArguments</key> <array><string>$BIN/m720d</string></array>
  <key>RunAtLoad</key>        <true/>
  <key>KeepAlive</key>        <true/>
  <key>ProcessType</key>      <string>Interactive</string>
  <key>StandardOutPath</key>  <string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "$TARGET" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 1

echo
echo "Installed:"
echo "  $BIN/m720d          the remapper"
echo "  $BIN/mouse          control it: start/stop/status/reload/logs/edit"
echo "  $PLIST"
echo "  $CONFIG"
echo "  $LOG"
echo
if ! grep -q "$BIN" <<<"$PATH"; then
    echo "NOTE: $BIN is not on your PATH. Add this to ~/.zshrc:"
    echo "      export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo
fi
if grep -q "could not create an event tap" "$LOG" 2>/dev/null; then
    cat <<'PERM'
>>> ACCESSIBILITY PERMISSION NEEDED <<<
    System Settings > Privacy & Security > Accessibility
    Add and enable:  ~/.local/bin/m720d
    (Cmd-Shift-G in the file picker to type the path.)
    Then:  mouse restart
PERM
else
    echo "Run 'mouse status' to check it, and 'mouse logs' if anything looks off."
fi

echo
echo "Uninstall:  launchctl bootout $TARGET; rm -f $BIN/m720d $BIN/mouse $PLIST"
