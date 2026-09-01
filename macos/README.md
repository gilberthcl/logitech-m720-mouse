# m720-config on macOS — feasibility probes

Same tool, same UI, different backend. Before writing that backend, two things
have to be established on the actual Mac, because they decide whether it is a
couple of days of work or not worth starting.

Run the probes, paste the output back.

## Run them

```bash
cd ~/m720-config/macos
./probe-1-hid.sh              # read-only, no permissions, installs nothing
# --- quit Logi Options+ from its menu bar icon before the next one ---
swift probe-2-events.swift    # needs Accessibility on your terminal (a toggle)
```

**Quit Logi Options+ first.** While it runs it grabs the buttons ahead of the
probe, so the results describe Options+ rather than the mouse. Probe 1 lists
what is running; probe 2 warns and keeps going if it finds anything.

Probe 2 only listens — it never swallows or alters an event, so the mouse
behaves normally while it runs. You can revoke the Accessibility toggle
afterwards.

It also prints keyboard **key codes** (numbers only, never characters), because
a button already remapped to a keystroke arrives as a keyboard event and would
otherwise look identical to a dead button. Nothing is stored or sent. Still:
don't type passwords while it runs.

## What each answers

**Probe 1** — is Secure Input stuck right now, and which process holds it; does
the M720 expose a vendor-specific HID collection (usage page `0xFF00`) alongside
the ordinary mouse one; is the Swift toolchain present.

**Probe 2** — which of the six controls actually produce events macOS can see,
and in what form. This is the decisive one. Each press prints one of:

| Output | Meaning |
|---|---|
| `BUTTON n` | raw button, remappable |
| `SCROLL horizontal` | wheel tilt, remappable |
| `KEY … keycode n` | something already remapped it — quit that software and re-run |
| nothing | invisible to macOS, needs a driver |

Expect middle click, back and forward as `button 2/3/4`, and the tilts as
horizontal scroll rather than buttons. The gesture button is the open question.

## What the answers mean

| Probe 2 result | Verdict |
|---|---|
| All six visible | Straightforward. Event-tap daemon, ~300 lines, full parity. |
| Five visible, gesture button silent | Build it for five. The gesture button needs HID++ divert, which needs the driver you can't install. |
| Accessibility toggle blocked by MDM | Stop. Nothing at this layer can work; it's an IT conversation. |

## Planned footprint

Everything user-level. No `sudo`, no `/etc`, no Homebrew, no pip, no system
extension.

```
~/.local/bin/m720d                    compiled Swift daemon, ~40 KB
~/.local/bin/mouse                    the same wrapper CLI
~/.local/lib/m720-config/             server.py + ui.html, essentially unchanged
~/Library/LaunchAgents/…m720.plist    user LaunchAgent, loaded with launchctl
~/.config/m720-config/                config.json + profiles.json
```

Build requirement is Xcode Command Line Tools for `swiftc`, once, at install
time. `server.py` is pure stdlib, so the UI needs nothing beyond the system
`python3`.

Uninstall is `launchctl bootout` plus deleting those five paths.

## What will still be broken, and why

**Secure Input.** An event-tap daemon cannot inject keystrokes while Secure
Input is active — same wall Options+ hits. No userland tool can get around it;
only a virtual HID driver can, and that's the system extension your Mac blocks.

What this tool *can* do that Options+ doesn't: detect the condition and tell
you. The UI would show "blocked right now by <app>" instead of leaving you to
wonder why a button went dead. Buttons mapped to non-keystroke actions
(Mission Control, workspace switching, volume) are unaffected either way.

So on macOS this is a partial tool. Worth being clear about that before
building it.

---

# The macOS remapper

The probes came back positive: all six controls are reachable through a plain
event tap. No driver, no system extension, no root.

| Control | How it arrives |
|---|---|
| Wheel click | `otherMouse` button 2 |
| Back | `otherMouse` button 3 |
| Forward | `otherMouse` button 4 |
| Wheel tilt L/R | `scrollWheel`, horizontal delta |
| Wheel rotation | `scrollWheel`, vertical delta |
| Gesture button | a `Ctrl+Up` **keystroke** from the mouse's own keyboard collection |

The gesture button is the interesting one. It is byte-identical to Ctrl+Up
typed on a keyboard except for the event's `keyboardType`: this mouse reports
**40**, the keyboard reports **41**. The daemon keys on that, so remapping the
gesture button does not hijack Ctrl+Up on your keyboard. If a future keyboard
also reports 40, re-run `probe-2-events.swift` and set `gestureKeyboardType`
in the config to match.

## Install

```bash
cd ~/m720-config/macos && ./install.sh
```

No sudo. It compiles `m720d` with `swiftc`, installs a LaunchAgent, and starts
it. Then grant Accessibility permission — **System Settings > Privacy &
Security > Accessibility**, add `~/.local/bin/m720d` (Cmd-Shift-G to type the
path) — and run `mouse restart`.

macOS ties that grant to the exact binary. `install.sh` therefore rebuilds
`m720d` only when `src/m720d.swift` has actually changed, so routine updates
keep your grant. Pass `--force` to rebuild anyway.

When it does rebuild, the grant goes stale even though the entry still shows
as enabled. Toggling it off and on sometimes suffices; if not, remove the
entry with the minus button and add it again. The daemon re-checks every
3 seconds, so it starts working on its own — no restart needed.

Everything lands under your home directory:

```
~/.local/bin/m720d                        the remapper (~40 KB)
~/.local/bin/mouse                        control CLI
~/Library/LaunchAgents/local.m720d.plist  user agent
~/.config/m720-config/config.json         configuration
~/Library/Logs/m720d.log                  log
```

## Use

The LaunchAgent is labelled `local.mouse`, so `launchctl` lists it as `mouse`.

| Command | Effect |
|---|---|
| `mouse start` / `mouse stop` | control the service |
| `mouse status` | is it running |
| `mouse log [N]` | last N log lines |
| `mouse edit` | edit config.json, then reload |
| `mouse reload` | re-read the config without dropping the tap |
| `mouse restart` | full restart |
| `mouse follow` | tail the log live |
| `mouse revert` | restore the previous config |

## Configuration

`~/.config/m720-config/config.json`. Control names are `button2` (wheel click),
`button3` (back), `button4` (forward), `tiltLeft`, `tiltRight`, `gesture`.

```json
{
  "buttons": {
    "button2":   { "type": "default" },
    "button3":   { "type": "keystroke", "keys": ["cmd", "c"] },
    "tiltLeft":  { "type": "keystroke", "keys": ["ctrl", "left"] },
    "gesture":   { "type": "default" }
  },
  "scroll": { "enabled": false, "multiplier": 3, "invert": false },
  "gestureKeyboardType": 40,
  "gestureEnabled": true
}
```

`type` is `default` (pass through untouched), `none` (disable), or `keystroke`.
Modifier names: `cmd`, `opt`, `ctrl`, `shift`, `fn`. Scroll speed is handled in
the daemon here — no imwheel equivalent is needed.

## Not done yet

- **The web UI.** `mouse modify` is Linux-only for now; the shared `server.py`
  writes `logid.cfg`. Wiring it to this JSON config is the next step.
- **Compiled and tested on a Mac.** The daemon was written without a macOS
  machine to build on. Expect the first `install.sh` to surface compile errors.
