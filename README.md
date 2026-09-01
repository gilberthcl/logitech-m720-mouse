# m720-config

A local web UI for remapping the buttons on a Logitech M720 Triathlon, wired
into the existing `mouse` service wrapper as `mouse modify`.

It is a front end for [logiops](https://github.com/PixlOne/logiops) — it writes
`/etc/logid.cfg` and restarts `mouse.service`. It does not talk to the mouse
itself.

## Install

Unpack this anywhere — `~/m720-config` is assumed throughout — then:

```bash
cd ~/m720-config && sudo ./install.sh && mouse modify
```

That opens `http://127.0.0.1:8770/?token=…` in your browser. Leave the terminal
running while you configure; Ctrl-C when done.

## What it does

`mouse` gains these subcommands:

| Command | Effect |
|---|---|
| `mouse modify` | open the configuration UI |
| `mouse logs [N]` | last N journal lines (default 50) |
| `mouse follow` | tail the journal live |
| `mouse edit` | edit `/etc/logid.cfg` by hand, then restart |
| `mouse revert` | roll back to the previous configuration |

`start`, `stop`, `restart`, `status`, `enable`, `disable` behave as before.

## The six buttons

The M720 exposes exactly six remappable HID++ control IDs:

| Button | cid |
|---|---|
| Wheel click | `0x52` |
| Back | `0x53` |
| Forward | `0x56` |
| Wheel tilt left | `0x5b` |
| Wheel tilt right | `0x5d` |
| Gesture (thumb) button | `0xd0` |

Left click, right click and wheel rotation are not remappable — the mouse
handles those in hardware and never reports them as assignable controls.

## Actions

Per button: **Default** (logid leaves it alone), **Keystroke** (a preset from
the Options+-style catalogue, or one you record by pressing the keys),
**Gestures** (four directions plus a plain click, thumb button only),
**Easy-Switch** (jump to paired computer 1/2/3, or next/previous),
**Cycle DPI**, or **Disable**.

Profiles are whole-configuration snapshots you name and switch between, stored
in `~/.config/m720-config/profiles.json`.

## Scroll speed

logiops has no scroll-speed setting — its only device-level knobs are `dpi`,
`smartshift`, `hiresscroll` and `thumbwheel`, none of which change how far a
ratcheted wheel scrolls. So the **Pointer & scroll** tab drives a second,
independent mechanism: [`imwheel`](https://manpages.debian.org/imwheel), the
standard X11 tool for this, which intercepts wheel buttons 4/5 and re-sends
them N times.

```bash
sudo apt install imwheel     # optional; the UI says so if it is missing
```

The UI writes `~/.imwheelrc`, restarts imwheel, and adds
`~/.config/autostart/m720-imwheel.desktop` so it comes back with your session.
None of that needs root.

Two details worth knowing:

- **Ctrl+scroll and Shift+scroll are passed through unmultiplied**, so zooming
  still moves one step at a time instead of leaping N steps.
- imwheel is launched with `-b "4 5"`, i.e. the vertical wheel only. Your
  remapped tilt buttons (6/7) are never touched.

Turning the setting off kills imwheel and removes the autostart entry; your
`~/.imwheelrc` is left in place.

Scroll speed applies independently of the button config: if a logid config is
rolled back, the scroll setting still takes effect, and the UI reports the two
results separately.

## Compared to Logi Options+

Supported: per-button assignment, custom keystroke recording, predefined
actions, thumb gestures, Easy-Switch, disabling a button, and scroll speed and
direction (through imwheel — see above).

Not supported, and why:

- **Per-application profiles.** logid has no window/app awareness at all. Named
  profiles you switch by hand are the substitute.
- **SmartShift / hi-res scroll.** The M720 has a ratcheted wheel with no
  free-spin clutch. Options+ hides these for this model too.
- **Pointer DPI.** logid has a `dpi` setting and the UI exposes it, but the M720
  may not implement the HID++ adjustable-DPI feature. Set it, apply, then check
  `mouse logs`; clear it if logid reports the feature is unsupported.
- **Pointer acceleration.** A libinput setting — use System Settings → Mouse &
  Touchpad. Neither logid nor imwheel controls it.
- **Battery level, firmware updates, Flow.** Out of scope for logiops.
- **Horizontal scroll as an assignable action.** logid's `Keypress` emits key
  codes, not scroll axes. Leave the wheel tilts on **Default** to keep native
  horizontal scrolling.

## Safety

Every Apply goes through `mouse-apply`, running as root via `pkexec` (or `sudo`):

1. Refuses an empty candidate, or one with no `devices:` block.
2. Copies the current `/etc/logid.cfg` to `/var/backups/m720-config/` — skipping
   the copy if the newest backup is already identical.
3. Installs the new config and restarts `mouse.service`.
4. Waits, then checks the unit is active and the journal is free of errors.
5. **If it is not, restores the backup and restarts** — your buttons keep
   working — and reports the journal tail in the UI.

`mouse revert` restores the newest backup that actually differs from what is
live, so a failed apply cannot shadow your last good configuration.

## Security notes

- The server binds `127.0.0.1` only and requires a token regenerated each run.
  Requests without it get 403, including the page itself.
- The HTTP server runs as **your user**, never root. All privileged work is the
  `mouse-apply` helper, which accepts a single file path and nothing else.
- Device names and key names are filtered before they reach the config file —
  key names must match `(KEY|BTN)_[A-Z0-9_]+`, and unknown control IDs are
  dropped rather than written through.

## Uninstall

```bash
sudo rm -rf /usr/local/lib/m720-config /usr/local/bin/mouse-apply
sudo mv /usr/local/bin/mouse.pre-m720-config /usr/local/bin/mouse   # if present
```

Your `/etc/logid.cfg` and `mouse.service` are left as they are.

## Known limitations

- Applying needs an authentication prompt each time unless your polkit session
  auth is still cached.
- `BTN_LEFT` / `BTN_MIDDLE` / `BTN_RIGHT` presets are listed as "test these":
  logid resolves them through libevdev, but mouse-button emission via uinput is
  worth confirming on your setup before relying on it.
- Scroll speed depends on imwheel, which is X11-only. On Wayland it will not
  work, and neither will the approach in general.
- Gesture mode is fixed to `OnRelease`. logid also has `OnFewPixels`,
  `OnThreshold`, `NoPress`, `Axis` and `Interval` modes, which the UI does not
  expose yet.
