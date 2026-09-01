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
    ps -p "$pid" -o pid=,comm= 2>/dev/null || echo "  (process is gone; stale entry)"
    echo "Quitting that app should release it."
fi

echo
echo "=============================================="
echo " 2. Logitech HID interfaces"
echo "=============================================="
# PrimaryUsagePage 1 / Usage 2 = a generic mouse.
# PrimaryUsagePage 65280 (0xFF00) = the vendor-specific HID++ collection —
# if that shows up, talking HID++ from userland may be possible, which is what
# it would take to reach the gesture button and tilts.
ioreg -c IOHIDDevice -r -l -w 0 2>/dev/null \
| awk '
  /^ *\+\-o /                { node=$0 }
  /"Product" =/              { prod=$0; show=1 }
  /"VendorID" =/             { vid=$0 }
  /"ProductID" =/            { pid=$0 }
  /"PrimaryUsagePage" =/     { pup=$0 }
  /"PrimaryUsage" =/         { pu=$0
                               if (show && (prod ~ /M720|Logi|Triathlon/ || vid ~ /1133/)) {
                                 gsub(/^ +/,"",prod); gsub(/^ +/,"",vid); gsub(/^ +/,"",pid)
                                 gsub(/^ +/,"",pup);  gsub(/^ +/,"",pu)
                                 print "  " prod; print "    " vid "  " pid
                                 print "    " pup "  " pu; print ""
                               }
                               show=0 }
'
echo "(VendorID 1133 = 0x046D = Logitech. If nothing printed, the mouse is"
echo " paired over Bluetooth and may appear only under IOBluetoothDevice.)"

echo
echo "=============================================="
echo " 3. Toolchain"
echo "=============================================="
if xcode-select -p >/dev/null 2>&1; then
    echo "Xcode command line tools: $(xcode-select -p)"
    swiftc --version 2>/dev/null | head -1 || echo "swiftc: NOT available"
else
    echo "Xcode command line tools: NOT installed"
    echo "  (would need: xcode-select --install)"
fi
python3 --version 2>/dev/null || echo "python3: NOT available"
