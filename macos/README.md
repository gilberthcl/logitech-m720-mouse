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
