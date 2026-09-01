#!/usr/bin/env bash
# Install the M720 remapper on macOS. Entirely user-level: no sudo, no
# /usr/local, no package manager, no system extension.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN="$HOME/.local/bin"
LIB="$HOME/.local/lib/m720-config"
CFG_DIR="$HOME/.config/m720-config"
CONFIG="$CFG_DIR/config.json"
LABEL=local.mouse
OLD_LABEL=local.m720d
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/m720d.log"
TARGET="gui/$(id -u)/$LABEL"

[[ $EUID -ne 0 ]] || { echo "do NOT run this with sudo — it installs into your home" >&2; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found. Run: xcode-select --install" >&2; exit 1; }

mkdir -p "$BIN" "$LIB" "$CFG_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# Rebuild only when the daemon source actually changed. macOS keys the
# Accessibility grant to the binary's hash, so an unnecessary recompile
# silently revokes permission and the user has to re-add it by hand.
SRC_HASH=$(shasum -a 256 "$SRC/src/m720d.swift" | awk '{print $1}')
STAMP="$LIB/.m720d.srchash"

if [[ ${1-} != "--force" && -x "$BIN/m720d" && -f $STAMP \
      && $(cat "$STAMP" 2>/dev/null) == "$SRC_HASH" ]]; then
    echo "m720d is already up to date — not rebuilding (keeps your Accessibility grant)"
else
    echo "compiling m720d…"
    swiftc -O -o "$BIN/m720d.new" "$SRC/src/m720d.swift" || {
        echo; echo "compile failed — nothing was installed or changed." >&2; exit 1; }
    mv "$BIN/m720d.new" "$BIN/m720d"

    # Ad-hoc sign it. TCC cannot reliably attribute an Accessibility grant to
    # an unsigned executable: the entry appears in the list and enables, but
    # the authorisation never matches the running process, so the event tap
    # keeps failing. A signature — even ad-hoc — gives it a stable identity.
    if codesign --force --sign - --identifier local.mouse.m720d "$BIN/m720d" 2>/dev/null; then
        echo "signed m720d (ad-hoc)"
    else
        echo "WARNING: could not codesign m720d; the Accessibility grant may not stick" >&2
    fi

    echo "$SRC_HASH" > "$STAMP"
    echo "NOTE: m720d was rebuilt, so its Accessibility grant may need re-adding."
fi

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

# Migrate from the old label so the service is simply "mouse".
if [[ -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist" ]]; then
    launchctl bootout "gui/$(id -u)/$OLD_LABEL" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
    echo "migrated service $OLD_LABEL -> $LABEL"
fi

# Remember where the log ends, so the checks below read only what this run
# appends. Grepping the whole file reports failures from previous runs
# forever, long after the permission has been granted.
LOG_MARK=$(wc -c < "$LOG" 2>/dev/null || echo 0)

launchctl bootout "$TARGET" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 2
THIS_RUN=$(tail -c "+$((LOG_MARK + 1))" "$LOG" 2>/dev/null || true)

echo
echo "Installed:"
echo "  $BIN/m720d          the remapper"
echo "  $BIN/mouse          control it: start / stop / status / log"
echo "  $PLIST"
echo "  $CONFIG"
echo "  $LOG"
echo
if ! grep -q "$BIN" <<<"$PATH"; then
    echo "NOTE: $BIN is not on your PATH. Add this to ~/.zshrc:"
    echo "      export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo
fi
if grep -q "event tap active" <<<"$THIS_RUN"; then
    echo "Event tap is ACTIVE — the remapper is working."
elif grep -q "no event tap yet" <<<"$THIS_RUN"; then
    cat <<PERM
>>> ACCESSIBILITY PERMISSION NEEDED <<<
    System Settings > Privacy & Security > Accessibility
    Add and enable:  $BIN/m720d

    m720d is running and re-checking every 3 seconds, so it will start
    working on its own once you grant it. No restart needed.

    If m720d is ALREADY listed and enabled: this install recompiled it, and
    macOS keys the grant to the exact binary. Toggle it off and on, or
    remove it with the minus button and add it again.
PERM
else
    echo "Started, but it logged nothing yet. Check with: mouse status"
fi

echo
echo "Uninstall:  launchctl bootout $TARGET; rm -f $BIN/m720d $BIN/mouse $PLIST"
