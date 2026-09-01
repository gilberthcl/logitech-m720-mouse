#!/usr/bin/env bash
# Probe 1 — what macOS sees of the M720, and whether Secure Input is stuck.
# Read-only. Installs nothing. Needs no permissions.
set -uo pipefail

echo "=============================================="
echo " 1. Secure Input"
echo "=============================================="
pid=$(ioreg -l -w 0 | awk -F'=' '/kCGSSessionSecureInputPID/{gsub(/ /,"",$2); print $2; exit}')
if [[ -z ${pid:-} || $pid == 0 ]]; then
    echo "Not active. Nothing is blocking keystroke injection right now."
else
    echo "ACTIVE — held by PID $pid:"
    ps -p "$pid" -o pid=,comm= 2>/dev/null || echo "  (process gone; stale entry)"
fi

echo
echo "=============================================="
echo " 2. Logitech software running"
echo "=============================================="
# Deliberately narrow: a bare 'logi' also matches macOS's own logind,
# loginwindow, login and LoginUserService, which drowns out the real answer.
if pgrep -il 'logioptions|logiplugin|logirightsight|logibolt|logimgr|logitune' 2>/dev/null; then
    echo
    echo ">>> QUIT LOGI OPTIONS+ BEFORE RUNNING PROBE 2. <<<"
    echo "    While it runs it intercepts the buttons and probe 2 measures"
    echo "    Options+, not the mouse."
else
    echo "None. Good — probe 2 will see the raw mouse."
fi

echo
echo "=============================================="
echo " 3. Logitech HID interfaces"
echo "=============================================="
ioreg -a -c IOHIDDevice -r -l 2>/dev/null | python3 -c '
import sys, plistlib

USAGE = {
    (1, 1): "Pointer", (1, 2): "Mouse", (1, 6): "Keyboard",
    (1, 7): "Keypad", (12, 1): "Consumer Control",
}

def walk(nodes):
    for n in nodes:
        if not isinstance(n, dict):
            continue
        yield n
        yield from walk(n.get("IORegistryEntryChildren", []))

try:
    data = plistlib.loads(sys.stdin.buffer.read())
except Exception as exc:
    print("  could not parse ioreg output:", exc)
    raise SystemExit

rows = []
for d in walk(data if isinstance(data, list) else [data]):
    if d.get("VendorID") != 1133:      # 0x046D Logitech
        continue
    up, u = d.get("PrimaryUsagePage"), d.get("PrimaryUsage")
    rows.append((d.get("Product", "?"), d.get("ProductID"), up, u,
                 d.get("Transport", "?")))

if not rows:
    print("  no Logitech HID devices found")
for r in sorted(set(rows)):
    prod, pid, up, u, tr = r
    kind = USAGE.get((up, u), "vendor-specific" if (up or 0) >= 0xFF00 else "other")
    star = "   <-- HID++ vendor collection" if (up or 0) >= 0xFF00 else ""
    print(f"  {prod:<22} pid=0x{pid:04x}  usagePage={up} usage={u}  ({kind})  {tr}{star}")
'
echo
echo "  A vendor-specific collection (usagePage >= 65280 / 0xFF00) is the HID++"
echo "  endpoint. Without it the gesture button and tilts cannot be diverted."

echo
echo "=============================================="
echo " 4. Toolchain"
echo "=============================================="
xcode-select -p 2>/dev/null || echo "Xcode CLT: NOT installed"
swiftc --version 2>/dev/null | head -1 || echo "swiftc: NOT available"
python3 --version 2>/dev/null || echo "python3: NOT available"
