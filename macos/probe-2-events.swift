// Probe 2 — which of the M720's six controls reach macOS, and in what form.
//
//     swift probe-2-events.swift
//
// Listen-only: it never modifies or swallows an event, so the mouse behaves
// normally while it runs. Ctrl-C to stop.
//
// PRIVACY: this prints keyboard *key codes* while running, because a button
// already remapped to a keystroke arrives as a keyboard event and would
// otherwise be invisible. It prints numeric codes only, never characters,
// only to your own terminal, and stores and sends nothing. Even so — do not
// type passwords while it is running, and close the terminal afterwards.
//
// Needs Accessibility on your terminal:
//     System Settings > Privacy & Security > Accessibility
// That is a permission toggle, not an install; you can switch it back off.

import Foundation
import Dispatch
import CoreGraphics

var seen = Set<String>()

// Naming the common codes matters: "ctrl+keycode 126" is unreadable, but
// "Ctrl+Up (Mission Control)" is obviously the gesture button.
let KEYNAME: [Int64: String] = [
    0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
    11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
    34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M",
    36:"Return", 48:"Tab", 49:"Space", 51:"Delete", 53:"Escape",
    115:"Home", 116:"PageUp", 119:"End", 121:"PageDown",
    123:"Left", 124:"Right", 125:"Down", 126:"Up",
]
let WELLKNOWN: [String: String] = [
    "ctrl+Up": "Mission Control", "ctrl+Down": "App Expose",
    "ctrl+Left": "Previous Desktop", "ctrl+Right": "Next Desktop",
    "cmd+C": "Copy", "cmd+V": "Paste",
]

func note(_ what: String) {
    if seen.insert(what).inserted { print("  NEW: \(what)") }
}

// Warn if Logitech software is still up — it intercepts the buttons first and
// this probe would then be measuring Options+ rather than the mouse.
func logitechRunning() -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-il", "logioptions|logiplugin|logirightsight|logibolt"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    try? p.run()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                     encoding: .utf8) ?? ""
    p.waitUntilExit()
    return out.split(separator: "\n").map(String.init)
}

let running = logitechRunning()
if !running.isEmpty {
    print("""
    ------------------------------------------------------------------
    WARNING — Logitech software is still running:
    \(running.map { "      " + $0 }.joined(separator: "\n"))

    Quit Logi Options+ from its menu bar icon and run this again, or the
    results below describe Options+ rather than your mouse.
    ------------------------------------------------------------------

    """)
}

let mask: CGEventMask =
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.scrollWheel.rawValue)    |
    (1 << CGEventType.keyDown.rawValue)

func handler(proxy: CGEventTapProxy, type: CGEventType,
             event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .otherMouseDown:
        let b = event.getIntegerValueField(.mouseEventButtonNumber)
        print("BUTTON  \(b)")
        note("button \(b)  — remappable")

    case .scrollWheel:
        let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        if dx != 0 {
            print("SCROLL  horizontal dx=\(dx)")
            note("wheel tilt — arrives as horizontal scroll, remappable")
        } else if dy != 0 {
            print("SCROLL  vertical dy=\(dy)")
            note("wheel rotation — vertical scroll")
        }

    case .keyDown:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let f = event.flags
        var mods: [String] = []
        if f.contains(.maskCommand)   { mods.append("cmd") }
        if f.contains(.maskAlternate) { mods.append("opt") }
        if f.contains(.maskControl)   { mods.append("ctrl") }
        if f.contains(.maskShift)     { mods.append("shift") }
        let m = mods.isEmpty ? "" : mods.joined(separator: "+") + "+"
        let named = m + (KEYNAME[code] ?? "keycode \(code)")
        let what = WELLKNOWN[named].map { " = \($0)" } ?? ""
        print("KEY     \(named)\(what)   <-- arrives as a keystroke, not a raw button")
        note("keystroke \(named)\(what) — reaches macOS, remappable with a caveat")

    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

// Prefer the HID tap: it sits closest to the hardware, ahead of session-level
// taps that other remappers install.
var placement = "HID (closest to hardware)"
var tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                            options: .listenOnly, eventsOfInterest: mask,
                            callback: handler, userInfo: nil)
if tap == nil {
    placement = "session (HID tap unavailable)"
    tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                            options: .listenOnly, eventsOfInterest: mask,
                            callback: handler, userInfo: nil)
}

guard let tap else {
    FileHandle.standardError.write("""
    Could not create an event tap.

    Grant Accessibility to your terminal:
      System Settings > Privacy & Security > Accessibility
    Add and enable your terminal app, then QUIT AND REOPEN it — the
    permission does not apply to an already-running process.

    If the toggle is greyed out or reverts, it is restricted by your MDM
    profile, which would also block the real tool. Stop there.

    """.data(using: .utf8)!)
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("""
Tap placement: \(placement)
Left and right click are ignored on purpose. Keyboard key codes are printed
(numbers only) — do not type passwords while this runs.

Press slowly, one at a time, pausing between each:
  1. WHEEL down (middle click)
  2. BACK           (rear thumb-side button)
  3. FORWARD        (front thumb-side button)
  4. tilt wheel LEFT
  5. tilt wheel RIGHT
  6. GESTURE button (big one on the thumb rest)
  7. scroll up, then down

  BUTTON n  = raw, remappable
  SCROLL    = raw, remappable
  KEY       = already remapped by other software, so quit that and re-run
  nothing   = invisible to macOS, needs a driver

Ctrl-C when done (it now exits cleanly), or it stops itself after 5 minutes.
""")

func summarise(_ why: String) -> Never {
    print("\n\n--- what produced events (\(why)) ---")
    if seen.isEmpty { print("  (nothing at all)") }
    for s in seen.sorted() { print("  \(s)") }
    print("\nAnything missing is not reachable without a driver.")
    exit(0)
}

for sig in [SIGINT, SIGTERM] { signal(sig, SIG_IGN) }
var signalSources: [DispatchSourceSignal] = []   // retained on purpose
for (sig, name) in [(SIGINT, "Ctrl-C"), (SIGTERM, "terminated")] {
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { summarise(name) }
    src.resume()
    signalSources.append(src)
}

// Backstop: never leave the user stuck in a process they cannot exit.
let LIMIT = 300.0
DispatchQueue.main.asyncAfter(deadline: .now() + LIMIT) {
    summarise("\(Int(LIMIT))s time limit")
}

CFRunLoopRun()
