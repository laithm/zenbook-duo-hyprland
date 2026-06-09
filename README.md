# zenbook-duo-hyprland

Setup tooling for the **ASUS Zenbook Duo (UX8406)** on **Hyprland**. It gets the
three things working that the laptop doesn't handle on its own under a tiling
Wayland setup:

1. **Dual-screen auto-toggle** - the bottom screen turns off when you fold the
   keyboard down over it, and back on when you lift it off. No more reaching for
   the terminal to `hyprctl ... disable` every time.
2. **Bluetooth keyboard auto-reconnect** - the detachable keyboard talks over
   the pogo pins when docked and over Bluetooth when detached. This bonds and
   trusts it so it reconnects by itself on every detach.
3. **Face unlock (Howdy)** - optional IR face login for `sudo`, `hyprlock`, and
   (if you want it) the SDDM login screen.

Everything is opt-in. Installing the package only drops files in place; nothing
on your system changes until you run `zenbook-duo-setup` and choose what you
want.

I wrote this for my own UX8406MA and figured other Duo owners on Hyprland could
use it too.

## Supported hardware

Built and tested on the **Zenbook Duo UX8406MA** (Intel Core Ultra, dual
2880x1800 panels, detachable keyboard). It should work on other UX8406 variants.
The model-specific defaults are the bottom panel name (`eDP-2`) and the
keyboard's USB id (`0b05:1b2c`); both are overridable in the config file if
yours differs. The setup script checks your DMI model and warns (but lets you
continue with `--force`) if you're on something else.

## Install

Once it's on the AUR:

```bash
yay -S zenbook-duo-hyprland
```

Until then, or to build from source:

```bash
git clone https://github.com/laithm/zenbook-duo-hyprland.git
cd zenbook-duo-hyprland
makepkg -si
```

Then run the setup once:

```bash
zenbook-duo-setup
```

It asks which of the three components you want and configures only those. You
can re-run it any time; every step is idempotent.

## What setup does

**Dual-screen auto-toggle.** Adds a small managed block to
`~/.config/hypr/userprefs.conf`:

```
# >>> zenbook-duo-hyprland >>>
exec-once = /usr/bin/zenbook-duo-screen
# <<< zenbook-duo-hyprland <<<
```

That daemon watches USB events. When the keyboard's USB device (`0b05:1b2c`)
appears it disables `eDP-2`; when it disappears it re-enables it. Restart
Hyprland (or just run `zenbook-duo-screen &`) to start it the first time.

If you'd rather run it as a systemd user service than via `exec-once`, there's a
unit at `/usr/share/zenbook-duo-hyprland/zenbook-duo-screen.service` you can copy
to `~/.config/systemd/user/` and enable. The `exec-once` route is the default
because `hyprctl` needs the compositor's environment, which an `exec-once` child
inherits for free.

**Bluetooth keyboard.** Detach the keyboard so it advertises, then setup pairs,
bonds, and trusts it and saves its MAC to `~/.config/zenbook-duo/config`. After
that it reconnects on its own whenever you detach.

**Face unlock (Howdy).** This one is careful on purpose:

- Offers to install `howdy-next` and `linux-enable-ir-emitter` via your AUR
  helper.
- Sets `workaround = off` in `/etc/howdy/config.ini` (the one setting that makes
  `pam_howdy` actually work on this hardware).
- Configures the IR emitter, enrolls your face, and runs `howdy test`.
- **Only after** the test passes does it touch PAM, and it backs up every file
  it edits to `*.zenbook-duo.bak` first.

Defaults to wiring `sudo` and `hyprlock`; the SDDM login screen is a separate
prompt since a mistake there is the most annoying to recover from.

## Configuration

Per-machine overrides live in `~/.config/zenbook-duo/config`. See
`/usr/share/zenbook-duo-hyprland/config.example`. The only value that genuinely
differs per unit is your keyboard's Bluetooth MAC (filled in for you by setup):

```bash
#BOTTOM="eDP-2"
#ON_MODE="preferred,0x900,2"
#KBD_VENDOR="0b05"
#KBD_PRODUCT="1b2c"
KBD_BT_MAC="AA:BB:CC:DD:EE:FF"
```

## Troubleshooting

```bash
zenbook-duo-setup --check        # model, monitors, keyboard USB/BT, howdy status
```

The screen daemon logs to `$XDG_RUNTIME_DIR/zenbook-duo-screen.log` - tail it
while you dock/undock to see what it's deciding.

If the bottom screen never turns off, check that the keyboard really does USB
disconnect on detach: `udevadm monitor --udev --subsystem-match=usb` and watch
for the remove event as you lift it.

Undo the face-unlock PAM changes:

```bash
zenbook-duo-setup --remove-faceid
```

## A note for hackers

The screen daemon reads `/sys/.../idVendor` with `cat`, not `$(<file
2>/dev/null)`. That looks like a pointless detail but it cost me an evening: in
**bash**, adding `2>/dev/null` to `$(<file)` disables the fast file-read and
returns an empty string, so detection silently thought the keyboard was always
detached. zsh reads it fine, which is exactly why it was confusing. If you hack
on this, keep the `cat`.

## License

MIT. See [LICENSE](LICENSE).
