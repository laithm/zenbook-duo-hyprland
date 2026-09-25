# zenbook-duo-hyprland

Small set of Arch Linux / Hyprland helpers for the **ASUS Zenbook Duo UX8406**.

I originally wrote these for my own UX8406MA because a few of the laptop's
hardware behaviours needed manual work under Hyprland:

- turn the lower display off when the detachable keyboard is docked, and back on
  when it is removed;
- keep the keyboard usable over Bluetooth when detached;
- optionally set up the IR camera for Howdy face unlock.

Installing the package only installs the files. Nothing is changed until you run
`zenbook-duo-setup`.

## Tested hardware

Built and tested on an **ASUS Zenbook Duo UX8406MA** with the dual 2880x1800
panels and detachable ASUS keyboard.

The defaults are:

```text
lower display: eDP-2
keyboard USB ID: 0b05:1b2c
```

Both can be overridden in `~/.config/zenbook-duo/config`.

I am moving away from this laptop, so I will not have permanent hardware access
for future Zenbook-specific changes. Issues, test results and pull requests from
other Duo owners are very welcome.

## Install

From the AUR:

```bash
yay -S zenbook-duo-hyprland
```

Or build it directly:

```bash
git clone https://github.com/laithm/zenbook-duo-hyprland.git
cd zenbook-duo-hyprland
makepkg -si
```

Then run:

```bash
zenbook-duo-setup
```

The setup asks which features you want and can be run again later.

## Dual-screen switching

When the keyboard is docked, it appears over the pogo-pin USB bridge as
`0b05:1b2c`. `zenbook-duo-screen` watches for that device:

```text
keyboard docked   -> disable eDP-2
keyboard detached -> enable eDP-2
```

Setup adds an `exec-once` block to your Hyprland config. If
`hyprland.conf` already sources `userprefs.conf`, it uses that file; otherwise
it writes the managed block to `hyprland.conf` itself.

The daemon logs to:

```text
$XDG_RUNTIME_DIR/zenbook-duo-screen.log
```

## Detachable keyboard

If the keyboard is already bonded, setup finds it and makes sure it is trusted.
Otherwise it scans while the keyboard is detached and asks for its Bluetooth
MAC before pairing.

The MAC is stored in:

```text
~/.config/zenbook-duo/config
```

## Face unlock

Face unlock is optional. The setup can install `howdy-next` and
`linux-enable-ir-emitter`, configure the IR emitter, enroll your face, and test
Howdy before touching PAM.

PAM files are backed up before they are edited. By default it configures `sudo`
and `hyprlock`; SDDM is a separate prompt.

Undo the PAM changes with:

```bash
zenbook-duo-setup --remove-faceid
```

## Diagnostics

```bash
zenbook-duo-setup --check
```

This prints the detected model, Hyprland monitors, keyboard USB state,
saved Bluetooth MAC and Howdy status.

If the lower screen never changes, check whether the keyboard really disappears
from USB when you lift it:

```bash
udevadm monitor --udev --subsystem-match=usb
```

## One odd Bash bug

The screen daemon deliberately uses `cat` for the USB ID files instead of
`$(<file 2>/dev/null)`.

That second form looked cleaner, but in Bash the redirect can disable the fast
file read and return an empty string. It cost me an evening because the daemon
then thought the keyboard was permanently detached. Keep the `cat` unless you
also change the error handling around it.

## License

MIT. See [LICENSE](LICENSE).
