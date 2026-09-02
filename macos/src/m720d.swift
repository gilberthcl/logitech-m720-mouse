// m720d — remaps the Logitech M720 Triathlon on macOS.
//
// A CGEventTap, nothing more: no driver, no system extension, no root.
// Needs Accessibility permission, which is a user-level toggle.
//
// What the probes established on this hardware:
//   wheel click    -> otherMouse button 2
//   back           -> otherMouse button 3
//   forward        -> otherMouse button 4
//   tilt left/right-> scrollWheel with a horizontal delta (axis 2)
//   wheel rotation -> scrollWheel with a vertical delta (axis 1)
//   gesture button -> a Ctrl+Up KEYSTROKE, not a button, distinguishable
//                     from a real keyboard only by keyboardType.

import Foundation
import Dispatch
import CoreGraphics

// ---------------------------------------------------------------- config

// Swift's synthesised Decodable IGNORES default values: a key missing from
// the JSON throws keyNotFound rather than falling back. That means adding any
// field to these structs silently breaks every existing config file. Decode
// every field with decodeIfPresent so old and new configs both load.

struct Action: Codable {
    var type: String = "default"     // default | none | keystroke | run
    var keys: [String]?              // e.g. ["cmd","c"]
    var command: String?             // e.g. "open -a 'Mission Control'"

    init() {}
    enum CodingKeys: String, CodingKey { case type, keys, command }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "default"
        keys = try c.decodeIfPresent([String].self, forKey: .keys)
        command = try c.decodeIfPresent(String.self, forKey: .command)
    }
}

struct ScrollConfig: Codable {
    var enabled: Bool = false
    var multiplier: Int = 3
    var invert: Bool = false

    init() {}
    enum CodingKeys: String, CodingKey { case enabled, multiplier, invert }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        multiplier = try c.decodeIfPresent(Int.self, forKey: .multiplier) ?? 3
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false
    }
}

struct Config: Codable {
    var buttons: [String: Action] = [:]
    var scroll = ScrollConfig()
    // keyboardType reported by the mouse's own keyboard collection. Events
    // whose keyboardType differs are a real keyboard and are never touched.
    // keyboardType values that identify the mouse's own keyboard collection.
    // A Bluetooth LE reconnect (after sleep) can change it, so this is a list:
    // add the new number when the log reports one rather than rebuilding.
    var gestureKeyboardTypes: [Int] = [40]
    var gestureKeyboardType: Int = 40      // legacy single value, merged in
    var gestureEnabled: Bool = true
    // Log every control the tap sees and what was done with it.
    var debug: Bool = true
    // How modifiers are sent: "flags" sets them on the key event (works
    // almost everywhere); "keys" also presses the physical modifier keys,
    // which some apps require. Switchable without recompiling.
    var postStyle: String = "flags"
    // Milliseconds to wait before sending a replacement keystroke, so the
    // originating button's own modifiers have been released first.
    var postDelayMs: Int = 20

    init() {}
    enum CodingKeys: String, CodingKey {
        case buttons, scroll, gestureKeyboardTypes, gestureKeyboardType,
             gestureEnabled, debug, postStyle, postDelayMs
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        buttons = try c.decodeIfPresent([String: Action].self, forKey: .buttons) ?? [:]
        scroll = try c.decodeIfPresent(ScrollConfig.self, forKey: .scroll) ?? ScrollConfig()
        gestureKeyboardType = try c.decodeIfPresent(Int.self, forKey: .gestureKeyboardType) ?? 40
        var types = try c.decodeIfPresent([Int].self, forKey: .gestureKeyboardTypes) ?? [40]
        if !types.contains(gestureKeyboardType) { types.append(gestureKeyboardType) }
        gestureKeyboardTypes = types
        gestureEnabled = try c.decodeIfPresent(Bool.self, forKey: .gestureEnabled) ?? true
        debug = try c.decodeIfPresent(Bool.self, forKey: .debug) ?? true
        postStyle = try c.decodeIfPresent(String.self, forKey: .postStyle) ?? "flags"
        postDelayMs = try c.decodeIfPresent(Int.self, forKey: .postDelayMs) ?? 20
    }
}

let CONFIG_PATH = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/m720-config/config.json")

var config = Config()
var configWatcher: DispatchSourceFileSystemObject?
// keyboardTypes already reported as unrecognised, so we warn once each.
var warnedKeyboardTypes = Set<Int>()

func loadConfig() {
    guard let data = try? Data(contentsOf: CONFIG_PATH) else {
        log("no config at \(CONFIG_PATH.path) — passing everything through")
        config = Config()
        return
    }
    do {
        config = try JSONDecoder().decode(Config.self, from: data)
        warnedKeyboardTypes.removeAll()
        log("config loaded: \(config.buttons.count) button(s), scroll " +
            (config.scroll.enabled ? "x\(config.scroll.multiplier)" : "off"))
    } catch {
        log("CONFIG ERROR — nothing will be remapped: \(error)")
        log("CONFIG ERROR — check \(CONFIG_PATH.path)")
    }
}

/// Reload whenever config.json changes on disk. SIGHUP proved unreliable in
/// practice, and this needs no signal, no wrapper cooperation, and no restart.
func watchConfig() {
    configWatcher?.cancel()
    let fd = Darwin.open(CONFIG_PATH.path, O_EVTONLY)
    guard fd >= 0 else { return }
    let src = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
    src.setEventHandler {
        loadConfig()
        // An editor that saves atomically replaces the inode we were watching,
        // so re-arm on the new file rather than watching a deleted one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { watchConfig() }
    }
    src.setCancelHandler { close(fd) }
    src.resume()
    configWatcher = src
}

func log(_ s: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    print("\(ts) m720d: \(s)")
    fflush(stdout)
}

// ------------------------------------------------------------- keystrokes

let KEYCODE: [String: CGKeyCode] = [
    "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
    "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,
    "6":22,"5":23,"equal":24,"9":25,"7":26,"minus":27,"8":28,"0":29,
    "rightbracket":30,"o":31,"u":32,"leftbracket":33,"i":34,"p":35,
    "return":36,"l":37,"j":38,"quote":39,"k":40,"semicolon":41,
    "backslash":42,"comma":43,"slash":44,"n":45,"m":46,"period":47,
    "tab":48,"space":49,"grave":50,"delete":51,"escape":53,
    "f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,
    "f9":101,"f10":109,"f11":103,"f12":111,
    "home":115,"pageup":116,"forwarddelete":117,"end":119,"pagedown":121,
    "left":123,"right":124,"down":125,"up":126,
]

let MODCODE: [String: CGKeyCode] = [
    "cmd": 55, "command": 55, "shift": 56, "opt": 58, "option": 58,
    "alt": 58, "ctrl": 59, "control": 59, "fn": 63,
]

let MODIFIER: [String: CGEventFlags] = [
    "cmd": .maskCommand, "command": .maskCommand,
    "opt": .maskAlternate, "option": .maskAlternate, "alt": .maskAlternate,
    "ctrl": .maskControl, "control": .maskControl,
    "shift": .maskShift, "fn": .maskSecondaryFn,
]

let eventSource = CGEventSource(stateID: .hidSystemState)
let BUTTON_NAMES = ["button2", "button3", "button4"]

func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
    if let e = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down) {
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }
}

/// Post one chord. Two styles, selectable in config without recompiling:
///   "flags" — modifiers ride on the key event. Correct for most apps.
///   "keys"  — the modifier keys are physically pressed around it as well,
///             which a few apps insist on before they honour the chord.
func postKeystroke(_ keys: [String]) {
    var flags: CGEventFlags = []
    var mods: [CGKeyCode] = []
    var codes: [CGKeyCode] = []
    for raw in keys {
        let k = raw.lowercased()
        if let m = MODIFIER[k] {
            flags.insert(m)
            if let mc = MODCODE[k] { mods.append(mc) }
        } else if let c = KEYCODE[k] {
            codes.append(c)
        } else {
            log("unknown key name \"\(raw)\" — ignored")
        }
    }
    guard !codes.isEmpty else { return }

    let useKeys = config.postStyle == "keys"
    if useKeys { for m in mods { post(m, true, flags) } }
    for c in codes { post(c, true, flags) }
    for c in codes.reversed() { post(c, false, flags) }
    if useKeys { for m in mods.reversed() { post(m, false, []) } }
}

// ------------------------------------------------------------------ tap

// Declared before callback(): top-level code cannot reference a variable
// that appears later in the file.
var globalTap: CFMachPort?

/// Decide what to do with a control. Returns true if the original event
/// should be swallowed.
func handleControl(_ name: String) -> Bool {
    guard let action = config.buttons[name] else {
        if config.debug { log("  \(name): not in config — passing through") }
        return false
    }
    switch action.type {
    case "none":
        if config.debug { log("  \(name): disabled — swallowed") }
        return true                       // disabled: swallow, emit nothing
    case "keystroke":
        guard let keys = action.keys, !keys.isEmpty else {
            if config.debug { log("  \(name): keystroke with no keys — passing through") }
            return false
        }
        if config.debug { log("  \(name): sending \(keys.joined(separator: "+")) — swallowed") }
        // Post asynchronously: a tap callback must return promptly or macOS
        // disables it for timing out. The small delay also lets the gesture
        // button's own Ctrl (a flagsChanged event we do not intercept) be
        // released first, so it cannot merge into the chord we send.
        let delay = Double(max(0, config.postDelayMs)) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { postKeystroke(keys) }
        return true
    case "run":
        // Some things cannot be reached by synthesising a keystroke at all.
        // Mission Control is the example: the physical F3 sends a special HID
        // usage, not virtual keycode 99, and Ctrl+Up is swallowed by
        // terminals. Running a command sidesteps focus and shortcut config
        // entirely.
        guard let cmd = action.command, !cmd.isEmpty else {
            if config.debug { log("  \(name): run with no command — passing through") }
            return false
        }
        if config.debug { log("  \(name): running `\(cmd)` — swallowed") }
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", cmd]
            do { try proc.run() } catch { log("  \(name): command failed: \(error)") }
        }
        return true

    default:
        if config.debug { log("  \(name): default — passing through untouched") }
        return false
    }
}

func callback(proxy: CGEventTapProxy, type: CGEventType,
              event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {

    // macOS disables a tap that takes too long, or across some login events.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        log("tap was disabled by the system — re-enabling")
        if let t = globalTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    switch type {
    case .otherMouseDown:
        let b = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if config.debug { log("saw mouse button \(b)") }
        let name: String? = (2...4).contains(b) ? BUTTON_NAMES[b - 2] : nil
        if let name, handleControl(name) { return nil }
        if config.debug && name == nil { log("  button \(b) is outside 2-4 — not remappable") }

    case .otherMouseUp:
        // Swallow the matching up-event for anything we swallowed on down,
        // otherwise applications see an unpaired release.
        let b = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if (2...4).contains(b), let a = config.buttons[BUTTON_NAMES[b - 2]],
           a.type == "none" || a.type == "keystroke" { return nil }

    case .scrollWheel:
        let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)

        if dx != 0 {
            if config.debug { log("saw wheel tilt dx=\(dx)") }
            if handleControl(dx > 0 ? "tiltLeft" : "tiltRight") { return nil }
        } else if dy != 0 && config.scroll.enabled {
            let sign: Int64 = config.scroll.invert ? -1 : 1
            let n = Int64(max(1, min(20, config.scroll.multiplier)))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: dy * n * sign)
            let pt = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            if pt != 0 {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1,
                                           value: pt * n * sign)
            }
        } else if dy != 0 && config.scroll.invert {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -dy)
        }

    case .keyDown, .keyUp:
        // The gesture button arrives as Ctrl+Up from the mouse's own keyboard
        // collection. Only touch it when keyboardType marks it as the mouse —
        // a real keyboard reports a different type and is left alone.
        guard config.gestureEnabled else { break }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let kbType = event.getIntegerValueField(.keyboardEventKeyboardType)
        guard code == 126, event.flags.contains(.maskControl) else { break }
        guard config.gestureKeyboardTypes.contains(Int(kbType)) else {
            // Not a keyboardType we know as the mouse. Say so once per value,
            // regardless of the debug setting: after a Bluetooth reconnect this
            // is the single most likely reason the gesture button "stopped
            // working", and the fix is to add this number to the config.
            if warnedKeyboardTypes.insert(Int(kbType)).inserted && type == .keyDown {
                log("Ctrl+Up seen from keyboardType \(kbType), which is not in " +
                    "gestureKeyboardTypes \(config.gestureKeyboardTypes).")
                log("  If that was the mouse's thumb button, add \(kbType) to " +
                    "gestureKeyboardTypes in \(CONFIG_PATH.path)")
            }
            break
        }
        if config.debug && type == .keyDown { log("saw gesture button (Ctrl+Up, kbType \(kbType))") }
        if type == .keyUp {
            if let a = config.buttons["gesture"],
               a.type == "none" || a.type == "keystroke" { return nil }
            break
        }
        if handleControl("gesture") { return nil }

    default:
        break
    }

    return Unmanaged.passUnretained(event)
}

// ----------------------------------------------------------------- main

loadConfig()

let mask: CGEventMask =
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue)   |
    (1 << CGEventType.scrollWheel.rawValue)    |
    (1 << CGEventType.keyDown.rawValue)        |
    (1 << CGEventType.keyUp.rawValue)

watchConfig()
log("started (config \(CONFIG_PATH.path), watching for changes)")

// Creating the tap fails until Accessibility permission is granted. Do NOT
// exit in that case: launchd has KeepAlive set, so exiting would respawn us
// every few seconds forever. Retry instead, and start working the moment the
// user grants it — no restart needed.
func makeTap() -> CFMachPort? {
    CGEvent.tapCreate(tap: .cghidEventTap,
                      place: .headInsertEventTap,
                      options: .defaultTap,      // must modify, not just listen
                      eventsOfInterest: mask,
                      callback: callback,
                      userInfo: nil)
}

func activate(_ tap: CFMachPort) {
    globalTap = tap
    defer { log("event tap active") }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
}

if let tap = makeTap() {
    activate(tap)
} else {
    log("no event tap yet — Accessibility permission is missing")
    log("grant it to \(CommandLine.arguments[0]) — this will pick it up automatically")
    let retry = DispatchSource.makeTimerSource(queue: .main)
    retry.schedule(deadline: .now() + 3, repeating: 3)
    retry.setEventHandler {
        if let tap = makeTap() {
            retry.cancel()
            activate(tap)
            log("Accessibility granted — tap active")
        }
    }
    retry.resume()
}

// SIGHUP reloads the config, so applying a change never drops the tap.
signal(SIGHUP, SIG_IGN)
let hup = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
hup.setEventHandler { log("SIGHUP — reloading config"); loadConfig() }
hup.resume()

CFRunLoopRun()
