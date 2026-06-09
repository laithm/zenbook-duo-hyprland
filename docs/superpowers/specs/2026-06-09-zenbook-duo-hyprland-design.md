# zenbook-duo-hyprland — design

An AUR package that brings the ASUS Zenbook Duo (UX8406-class) to life under
Hyprland: dual-screen auto-toggle on keyboard dock/detach, Bluetooth keyboard
auto-reconnect, and optional Howdy IR face unlock. Distribution is an AUR
package; configuration is a one-shot interactive `zenbook-duo-setup` that asks
what you want before changing anything on the machine.

## Goals

- One install command for other Zenbook Duo + Hyprland users (`yay -S zenbook-duo-hyprland`).
- Nothing device-altering happens at package-install time. `pacman`/`yay` only
  place files. The user runs `zenbook-duo-setup` once and opts into each piece.
- Works out of the box on a UX8406 with sensible baked-in defaults; per-unit
  values (the keyboard's Bluetooth MAC) are detected/prompted, not hardcoded.
- Safe by construction: PAM edits are backed up and gated behind successful face
  enrollment, and every step is idempotent / re-runnable.

## Non-goals

- Supporting non-Zenbook-Duo hardware (a `--force` escape hatch exists, but it is
  not a target).
- Supporting compositors other than Hyprland.
- Auto-updating device-specific config after the first setup run.

## Architecture

Package installs (read-only, system locations):

```
/usr/bin/zenbook-duo-screen          the eDP-2 auto-toggle daemon (generalized)
/usr/bin/zenbook-duo-setup           interactive opt-in installer / menu
/usr/lib/zenbook-duo-hyprland/       step scripts: screen.sh, keyboard.sh, faceid.sh, common.sh
/usr/share/zenbook-duo-hyprland/     templates: exec-once.snippet, config.example,
                                     zenbook-duo-screen.service (optional)
/usr/share/doc/zenbook-duo-hyprland/ README, LICENSE
```

Setup writes (per-user / per-machine, only for chosen components):

```
~/.config/zenbook-duo/config         device-specific values (monitor, kbd id, BT MAC)
~/.config/hypr/userprefs.conf        managed exec-once block (begin/end markers, idempotent)
/etc/howdy/config.ini                workaround=off                       (Face ID only)
/etc/pam.d/{sudo,hyprlock,sddm}      pam_howdy lines, with .bak backups    (Face ID only)
```

### Configuration model

The daemon today hardcodes `eDP-2`, the keyboard USB id `0b05:1b2c`, and a
specific Bluetooth MAC. In the package:

- Model-wide values (`BOTTOM=eDP-2`, `ON_MODE=preferred,0x900,2`,
  `KBD_VENDOR=0b05`, `KBD_PRODUCT=1b2c`) become baked-in defaults inside the
  daemon, so it runs correctly on a stock UX8406 with no config.
- The per-unit value (Bluetooth keyboard MAC) is discovered by setup and written
  to `~/.config/zenbook-duo/config`.
- The daemon sources `~/.config/zenbook-duo/config` if present and falls back to
  defaults for anything unset. Keys: `BOTTOM`, `ON_MODE`, `KBD_VENDOR`,
  `KBD_PRODUCT`, `KBD_BT_MAC`.

## Components

### 1. Screen auto-toggle (`zenbook-duo-screen`)

Carries over the proven logic verbatim:

- Detection: keyboard present as USB `0b05:1b2c` = docked → `hyprctl keyword
  monitor eDP-2,disable`; absent = detached → `eDP-2,<ON_MODE>`.
- Read sysfs with `cat "$f" 2>/dev/null`, **never** `$(<file 2>/dev/null)` (that
  returns an empty string in bash and silently breaks detection).
- Event loop via `stdbuf -oL udevadm monitor --udev --subsystem-match=usb` and
  process substitution; `apply()` is stateless and idempotent, logs only on
  change.

Delivery: a **managed `exec-once` block** appended to `~/.config/hypr/userprefs.conf`
between `# >>> zenbook-duo-hyprland >>>` / `# <<<` markers (idempotent: setup
rewrites the block, never duplicates it). Rationale: `hyprctl` needs the
compositor environment, which an `exec-once` child inherits for free; a systemd
user unit would require `systemctl --user import-environment`, which not every
Hyprland setup performs. A `zenbook-duo-screen.service` user unit is shipped as
an opt-in alternative for users who prefer it.

### 2. Bluetooth keyboard (`keyboard.sh`)

When detached, the keyboard switches from pogo-pin USB to Bluetooth. Setup:

- If a Zenbook Duo keyboard is already bonded, ensure it is `trust`ed and record
  its MAC.
- Otherwise run a guided `bluetoothctl` pair → bond → trust (power on, pairable
  on, scan, prompt user to detach so the keyboard advertises).
- Save the discovered MAC to config as `KBD_BT_MAC`.

Bonded + trusted means it auto-reconnects on every detach. The MAC is only used
for diagnostics (`zenbook-duo-setup --check`), not by the screen daemon.

### 3. Face ID / Howdy (`faceid.sh`) — opt-in, safety-first

- `optdepends`: `howdy-next`, `linux-enable-ir-emitter`. Setup offers to install
  them (via the user's AUR helper) only when this component is chosen.
- Run `linux-enable-ir-emitter` configuration for the IR camera.
- Set `workaround=off` in `/etc/howdy/config.ini` (the documented gotcha).
- Enrollment first: run `howdy add`; only after a successful `howdy test` does it
  wire `pam_howdy` into the selected `/etc/pam.d` files.
- Every `/etc/pam.d` file edited is copied to `<file>.zenbook-duo.bak` first.
- `zenbook-duo-setup --remove-faceid` restores backups and removes the pam lines.

Default PAM targets: `sudo` and `hyprlock`. `sddm` (login screen) offered
separately as a more aggressive opt-in, since a misconfiguration there is the
most disruptive.

## Interactive setup flow (`zenbook-duo-setup`)

1. **Hardware guard:** read `/sys/class/dmi/id/product_name`; if it does not match
   `Zenbook Duo`, warn and require `--force` to continue.
2. **Component menu:** checkbox-style selection of the three components (plain
   `read` prompts; no hard dependency on whiptail/gum).
3. **Run chosen steps** idempotently. Re-running setup is safe and re-asserts
   state rather than duplicating it.

Flags: `--force` (skip hardware guard), `--check` (diagnostics: monitors,
keyboard USB/BT state, howdy status), `--remove-faceid` (rollback PAM changes).

## Packaging

- **PKGBUILD:** versioned release `v0.1.0`; `source` = GitHub release tarball
  pinned by `sha256sums`. `arch=(any)` (shell scripts only).
  - `depends`: `hyprland`, `bash`, `bluez-utils`, `systemd` (for `udevadm`).
  - `optdepends`: `howdy-next`, `linux-enable-ir-emitter`.
- `.SRCINFO` generated with `makepkg --printsrcinfo`.
- Build verified locally with `makepkg -f` before publishing.

## Repo, license, voice

- GitHub: public `laithm/zenbook-duo-hyprland`.
- License: MIT, authored to Laith Masri.
- README and all code comments are written in a plain, human, first-person voice.
- Commits are authored as `laithm`; **no AI attribution trailer** in this repo.

## Deliverables (first iteration)

1. Repo scaffold under `~/Documents/zenbook-duo-hyprland`.
2. `zenbook-duo-screen`, `zenbook-duo-setup`, and the `screen.sh` / `keyboard.sh`
   / `faceid.sh` / `common.sh` step scripts.
3. Templates: `exec-once.snippet`, `config.example`, `zenbook-duo-screen.service`.
4. `PKGBUILD` + `.SRCINFO`, build-tested with `makepkg`.
5. README + MIT LICENSE.
6. Push to GitHub, tag `v0.1.0`, create the release.
7. Copy-paste instructions for publishing to the AUR once the account/SSH key is
   ready.
