// Probe 2 — which of the M720's six controls actually reach macOS.
//
// Run without installing anything:
//     swift probe-2-events.swift
//
// It only listens (.listenOnly) — it never modifies or swallows an event, so
// your mouse behaves normally while it runs. Ctrl-C to stop.
//
// The first run will fail unless your terminal has Accessibility permission:
//     System Settings > Privacy & Security > Accessibility > enable Terminal
// That is a permission toggle, not an install, and you can switch it back off.

import Foundation
import CoreGraphics

var seen = Set<String>()

func note(_ what: String) {
    if seen.insert(what).inserted {
        print("  NEW: \(what)")
    }
}

let mask: CGEventMask =
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue)   |
    (1 << CGEventType.scrollWheel.rawValue)

func handler(proxy: CGEventTapProxy, type: CGEventType,
             event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .otherMouseDown:
        let b = event.getIntegerValueField(.mouseEventButtonNumber)
        print("button \(b) down")
        note("button \(b)")

    case .scrollWheel:
        let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        if dx != 0 {
            print("horizontal scroll  dx=\(dx)")
            note("wheel tilt (horizontal scroll, dx)")
        } else if dy != 0 {
            print("vertical scroll    dy=\(dy)")
            note("wheel rotation (vertical scroll, dy)")
        }

    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                  place: .headInsertEventTap,
                                  options: .listenOnly,
                                  eventsOfInterest: mask,
                                  callback: handler,
                                  userInfo: nil) else {
    FileHandle.standardError.write("""
    Could not create an event tap.

    Your terminal needs Accessibility permission:
      System Settings > Privacy & Security > Accessibility
    Add and enable your terminal app, then run this again.

    If the toggle is greyed out or reverts, it is restricted by your MDM
    profile — which would also block the real tool, so stop here.

    """.data(using: .utf8)!)
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("""
Listening. Left and right click are ignored on purpose.

Now, one at a time:
  1. press the WHEEL down (middle click)
  2. press BACK          (rear thumb-side button)
  3. press FORWARD       (front thumb-side button)
  4. tilt the wheel LEFT
  5. tilt the wheel RIGHT
  6. press the big GESTURE button on the thumb rest
  7. scroll up and down

Anything that prints nothing is invisible to macOS at this layer, and cannot
be remapped without a driver. Ctrl-C when done.
""")

signal(SIGINT) { _ in
    print("\n\n--- controls that produced events ---")
    for s in seen.sorted() { print("  \(s)") }
    print("\nAnything missing from that list is not reachable without a driver.")
    exit(0)
}

CFRunLoopRun()
