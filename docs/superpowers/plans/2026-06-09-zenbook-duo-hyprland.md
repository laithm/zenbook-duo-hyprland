# zenbook-duo-hyprland Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an AUR-distributable package that sets up dual-screen auto-toggle, Bluetooth keyboard auto-reconnect, and optional Howdy face unlock for ASUS Zenbook Duo (UX8406) users on Hyprland, driven by a safe interactive `zenbook-duo-setup`.

**Architecture:** Package installs read-only scripts/templates to `/usr/bin`, `/usr/lib`, `/usr/share`. A one-shot `zenbook-duo-setup` asks which components to enable, then configures them idempotently with per-machine state in `~/.config/zenbook-duo/config`. Nothing device-altering runs at package-install time.

**Tech Stack:** Bash, udev (`udevadm`), `hyprctl`, `bluetoothctl`, Howdy (`howdy-next`) + `linux-enable-ir-emitter`, Arch PKGBUILD/makepkg. Verification: `shellcheck` + `makepkg` build + smoke checks.

---

### Task 1: Repo scaffold + LICENSE + .gitignore

**Files:**
- Create: `~/Documents/zenbook-duo-hyprland/LICENSE`
- Create: `~/Documents/zenbook-duo-hyprland/.gitignore`

- [ ] **Step 1:** Write MIT `LICENSE`, copyright `2026 Laith Masri`.
- [ ] **Step 2:** Write `.gitignore` ignoring `pkg/`, `src/`, `*.pkg.tar.zst`, `*.tar.gz`.
- [ ] **Step 3:** Commit `chore: license and gitignore`.

---

### Task 2: `common.sh` shared helpers

**Files:**
- Create: `lib/common.sh`

Responsibilities: logging helpers, config path resolution, config load/save, hardware guard, AUR-helper detection. Sourced by all step scripts.

- [ ] **Step 1:** Implement and `shellcheck lib/common.sh`.

```bash
#!/usr/bin/env bash
# Shared helpers for zenbook-duo-hyprland setup steps.

ZD_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zenbook-duo"
ZD_CONFIG="$ZD_CONFIG_DIR/config"

# Baked-in defaults for a stock UX8406. Overridable via the config file.
: "${BOTTOM:=eDP-2}"
: "${ON_MODE:=preferred,0x900,2}"
: "${KBD_VENDOR:=0b05}"
: "${KBD_PRODUCT:=1b2c}"
: "${KBD_BT_MAC:=}"

msg()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; }

ask_yn() {  # ask_yn "prompt" default(y/n) -> returns 0 for yes
    local prompt="$1" def="${2:-n}" ans
    local hint="[y/N]"; [ "$def" = y ] && hint="[Y/n]"
    read -r -p "$prompt $hint " ans
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[Yy] ]]
}

load_config() { [ -r "$ZD_CONFIG" ] && . "$ZD_CONFIG"; }

save_config_kv() {  # save_config_kv KEY VALUE  (idempotent upsert)
    local key="$1" val="$2"
    mkdir -p "$ZD_CONFIG_DIR"
    touch "$ZD_CONFIG"
    if grep -q "^${key}=" "$ZD_CONFIG" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$ZD_CONFIG"
    else
        printf '%s="%s"\n' "$key" "$val" >> "$ZD_CONFIG"
    fi
}

is_zenbook_duo() {
    local m
    m=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    [[ "$m" == *"Zenbook Duo"* ]]
}

aur_helper() {
    for h in yay paru; do command -v "$h" >/dev/null && { echo "$h"; return 0; }; done
    return 1
}
```

- [ ] **Step 2:** Commit `feat: shared setup helpers (common.sh)`.

---

### Task 3: `zenbook-duo-screen` daemon (generalized)

**Files:**
- Create: `bin/zenbook-duo-screen`

Port the proven daemon; read overrides from `~/.config/zenbook-duo/config`; keep the `cat`-not-`$(<…)` fix and `stdbuf -oL` udev loop.

- [ ] **Step 1:** Implement.

```bash
#!/usr/bin/env bash
# Auto-toggle the Zenbook Duo bottom screen based on whether the magnetic
# keyboard is docked. Docked (keyboard USB present) -> bottom screen off.
# Detached -> bottom screen on. Launched from Hyprland so hyprctl inherits
# the compositor environment.

set -u

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/zenbook-duo/config"

# Defaults for a stock UX8406; the config file may override any of these.
BOTTOM="eDP-2"
ON_MODE="preferred,0x900,2"
KBD_VENDOR="0b05"
KBD_PRODUCT="1b2c"
# shellcheck source=/dev/null
[ -r "$CONFIG" ] && . "$CONFIG"

ON_ARGS="${BOTTOM},${ON_MODE}"
LOGFILE="${XDG_RUNTIME_DIR:-/tmp}/zenbook-duo-screen.log"
log() { printf '%s zenbook-duo-screen: %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOGFILE"; }

kbd_docked() {
    local d vid pid
    for d in /sys/bus/usb/devices/*; do
        [ -r "$d/idVendor" ] || continue
        # Use cat, not $(<file 2>/dev/null): in bash the redirect disables the
        # fast file-read and yields an empty string, which silently breaks this.
        vid=$(cat "$d/idVendor" 2>/dev/null)
        pid=$(cat "$d/idProduct" 2>/dev/null)
        [ "$vid" = "$KBD_VENDOR" ] && [ "$pid" = "$KBD_PRODUCT" ] && return 0
    done
    return 1
}

apply() {
    local want
    if kbd_docked; then want="off"; else want="on"; fi
    [ "$want" = "$STATE" ] && return
    if [ "$want" = "off" ]; then
        log "keyboard docked -> disabling $BOTTOM"
        hyprctl keyword monitor "${BOTTOM},disable" >/dev/null
    else
        log "keyboard detached -> enabling $BOTTOM"
        hyprctl keyword monitor "$ON_ARGS" >/dev/null
    fi
    STATE="$want"
}

STATE="unknown"
apply
while read -r _; do
    sleep 0.4
    apply
done < <(stdbuf -oL udevadm monitor --udev --subsystem-match=usb 2>/dev/null)
```

- [ ] **Step 2:** `shellcheck bin/zenbook-duo-screen` (expect clean, source line disabled).
- [ ] **Step 3:** Smoke: run `bash -n bin/zenbook-duo-screen` (syntax OK) and confirm `kbd_docked` reads sysfs by running an inline copy of the function. Expected: exit 0/1, no errors.
- [ ] **Step 4:** Commit `feat: generalized screen auto-toggle daemon`.

---

### Task 4: Templates (exec-once, config example, systemd unit)

**Files:**
- Create: `share/exec-once.snippet`
- Create: `share/config.example`
- Create: `share/zenbook-duo-screen.service`

- [ ] **Step 1:** `share/exec-once.snippet`:

```
# >>> zenbook-duo-hyprland >>>
exec-once = /usr/bin/zenbook-duo-screen
# <<< zenbook-duo-hyprland <<<
```

- [ ] **Step 2:** `share/config.example`:

```bash
# ~/.config/zenbook-duo/config — device overrides for zenbook-duo-hyprland.
# Defaults shown; uncomment to change. Only KBD_BT_MAC is per-unit.
#BOTTOM="eDP-2"
#ON_MODE="preferred,0x900,2"
#KBD_VENDOR="0b05"
#KBD_PRODUCT="1b2c"
#KBD_BT_MAC=""
```

- [ ] **Step 3:** `share/zenbook-duo-screen.service` (optional user unit):

```ini
[Unit]
Description=Zenbook Duo bottom-screen auto-toggle
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/bin/zenbook-duo-screen
Restart=on-failure

[Install]
WantedBy=graphical-session.target
```

- [ ] **Step 4:** Commit `feat: exec-once, config, and systemd templates`.

---

### Task 5: `screen.sh` step (install exec-once block)

**Files:**
- Create: `lib/screen.sh`

Idempotent managed-block writer into `~/.config/hypr/userprefs.conf`.

- [ ] **Step 1:** Implement.

```bash
#!/usr/bin/env bash
# Enable the screen auto-toggle daemon by adding a managed exec-once block to
# the user's Hyprland config. Idempotent: rewrites the block, never duplicates.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"

SNIPPET="/usr/share/zenbook-duo-hyprland/exec-once.snippet"
USERPREFS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/userprefs.conf"
BEGIN="# >>> zenbook-duo-hyprland >>>"
END="# <<< zenbook-duo-hyprland <<<"

setup_screen() {
    msg "Configuring dual-screen auto-toggle"
    if [ ! -f "$USERPREFS" ]; then
        warn "No $USERPREFS found; creating it."
        mkdir -p "$(dirname "$USERPREFS")"; touch "$USERPREFS"
    fi
    # Drop any existing managed block, then append a fresh one.
    sed -i "/$BEGIN/,/$END/d" "$USERPREFS"
    # Trim trailing blank lines, then append.
    printf '\n%s\n' "$(cat "${SNIPPET:-/dev/null}" 2>/dev/null || cat "$HERE/../share/exec-once.snippet")" >> "$USERPREFS"
    ok "exec-once block written to $USERPREFS"
    msg "Restart Hyprland (or run the daemon now) to activate."
}
```

- [ ] **Step 2:** `shellcheck lib/screen.sh`.
- [ ] **Step 3:** Smoke: set `USERPREFS=/tmp/up.conf`, source and run `setup_screen` twice; verify exactly one managed block exists (`grep -c "$BEGIN" /tmp/up.conf` == 1).
- [ ] **Step 4:** Commit `feat: screen.sh installs managed exec-once block`.

---

### Task 6: `keyboard.sh` step (Bluetooth pair/bond/trust)

**Files:**
- Create: `lib/keyboard.sh`

- [ ] **Step 1:** Implement.

```bash
#!/usr/bin/env bash
# Pair/bond/trust the detachable keyboard over Bluetooth so it auto-reconnects
# on detach. If already bonded, just ensure trust and record the MAC.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"

# Find an already-known device whose name looks like the Zenbook keyboard.
find_known_kbd() {
    bluetoothctl devices Bonded 2>/dev/null | while read -r _ mac _; do
        local name; name=$(bluetoothctl info "$mac" 2>/dev/null | sed -n 's/^\tName: //p')
        [[ "$name" == *Keyboard* || "$name" == *ZenBook* || "$name" == *Zenbook* ]] && { echo "$mac"; return; }
    done
}

setup_keyboard() {
    msg "Configuring Bluetooth keyboard"
    command -v bluetoothctl >/dev/null || { err "bluez-utils not installed."; return 1; }
    bluetoothctl power on >/dev/null 2>&1

    local mac; mac=$(find_known_kbd)
    if [ -n "$mac" ]; then
        ok "Found bonded keyboard: $mac"
    else
        warn "No bonded keyboard found."
        echo "Detach the keyboard now so it advertises over Bluetooth, then continue."
        ask_yn "Scan and pair now?" y || { warn "Skipped keyboard setup."; return 0; }
        bluetoothctl --timeout 20 scan on >/dev/null 2>&1
        echo "Devices seen:"; bluetoothctl devices
        read -r -p "Enter the keyboard's MAC (AA:BB:CC:DD:EE:FF): " mac
        [ -z "$mac" ] && { err "No MAC given."; return 1; }
        bluetoothctl pair "$mac"
    fi

    bluetoothctl trust "$mac" >/dev/null 2>&1
    bluetoothctl connect "$mac" >/dev/null 2>&1 || true
    save_config_kv KBD_BT_MAC "$mac"
    ok "Keyboard $mac trusted; saved to config. It will auto-reconnect on detach."
}
```

- [ ] **Step 2:** `shellcheck lib/keyboard.sh`.
- [ ] **Step 3:** Smoke: `bash -n lib/keyboard.sh`. (Live pairing needs hardware; not run in build.)
- [ ] **Step 4:** Commit `feat: keyboard.sh bonds/trusts the BT keyboard`.

---

### Task 7: `faceid.sh` step (Howdy, safety-first) + rollback

**Files:**
- Create: `lib/faceid.sh`

- [ ] **Step 1:** Implement.

```bash
#!/usr/bin/env bash
# Optional Howdy IR face unlock. Installs deps on request, applies the
# workaround=off fix, enrolls a face, and only then wires pam_howdy into the
# chosen PAM services. Every edited pam.d file is backed up first.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"

PAM_LINE="auth sufficient pam_howdy.so"
BAK_SUFFIX=".zenbook-duo.bak"

ensure_deps() {
    pacman -Qq howdy-next >/dev/null 2>&1 && return 0
    local h; h=$(aur_helper) || { err "No AUR helper (yay/paru) found; install howdy-next manually."; return 1; }
    ask_yn "Install howdy-next + linux-enable-ir-emitter via $h?" y || return 1
    "$h" -S --needed howdy-next linux-enable-ir-emitter
}

wire_pam() {  # wire_pam /etc/pam.d/sudo
    local f="$1"
    [ -f "$f" ] || { warn "$f missing, skipping."; return; }
    grep -q pam_howdy "$f" && { ok "$f already has howdy."; return; }
    sudo cp -n "$f" "${f}${BAK_SUFFIX}"
    sudo sed -i "1i $PAM_LINE" "$f"
    ok "Added howdy to $f (backup: ${f}${BAK_SUFFIX})"
}

setup_faceid() {
    msg "Configuring Howdy face unlock"
    ensure_deps || return 1
    # The documented gotcha: pam_howdy needs workaround=off.
    if [ -f /etc/howdy/config.ini ]; then
        sudo sed -i 's/^workaround = .*/workaround = off/' /etc/howdy/config.ini
        ok "Set workaround=off in /etc/howdy/config.ini"
    fi
    msg "Configuring the IR emitter (may prompt)."
    command -v linux-enable-ir-emitter >/dev/null && sudo linux-enable-ir-emitter configure || warn "Configure the IR emitter manually if face detection fails."
    msg "Enroll your face now."
    sudo howdy add || { err "Enrollment failed; not touching PAM."; return 1; }
    if ! sudo howdy test; then
        err "howdy test failed; refusing to wire PAM. Re-run after fixing the camera."
        return 1
    fi
    wire_pam /etc/pam.d/sudo
    wire_pam /etc/pam.d/hyprlock
    if ask_yn "Also enable face unlock at the SDDM login screen?" n; then
        wire_pam /etc/pam.d/sddm
    fi
    ok "Face unlock configured. Test with: sudo -k; sudo true"
}

remove_faceid() {
    msg "Removing Howdy PAM integration"
    local f
    for f in /etc/pam.d/sudo /etc/pam.d/hyprlock /etc/pam.d/sddm; do
        if [ -f "${f}${BAK_SUFFIX}" ]; then
            sudo mv "${f}${BAK_SUFFIX}" "$f"; ok "Restored $f"
        elif grep -q pam_howdy "$f" 2>/dev/null; then
            sudo sed -i '/pam_howdy/d' "$f"; ok "Stripped howdy line from $f"
        fi
    done
}
```

- [ ] **Step 2:** `shellcheck lib/faceid.sh`.
- [ ] **Step 3:** Smoke: `bash -n lib/faceid.sh`. (Live enroll needs hardware; not run in build.)
- [ ] **Step 4:** Commit `feat: faceid.sh installs Howdy safely with rollback`.

---

### Task 8: `zenbook-duo-setup` orchestrator

**Files:**
- Create: `bin/zenbook-duo-setup`

Resolves lib dir (installed `/usr/lib/...` or repo-local for dev), parses flags, runs the guard + menu, dispatches steps.

- [ ] **Step 1:** Implement.

```bash
#!/usr/bin/env bash
# Interactive, opt-in setup for zenbook-duo-hyprland. Nothing is changed until
# you choose a component. Re-runnable and idempotent.
set -u

# Locate the step-script library (installed path first, then repo-local).
for cand in /usr/lib/zenbook-duo-hyprland "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)"; do
    [ -r "$cand/common.sh" ] && { LIBDIR="$cand"; break; }
done
: "${LIBDIR:?cannot find zenbook-duo-hyprland lib dir}"
# shellcheck source=/dev/null
. "$LIBDIR/common.sh"; . "$LIBDIR/screen.sh"; . "$LIBDIR/keyboard.sh"; . "$LIBDIR/faceid.sh"

FORCE=0
usage() { cat <<EOF
zenbook-duo-setup — set up Zenbook Duo features on Hyprland
  (no args)        interactive menu
  --force          skip the Zenbook Duo hardware check
  --check          print diagnostics and exit
  --remove-faceid  undo Howdy PAM changes and exit
  -h, --help       this help
EOF
}

do_check() {
    load_config
    msg "Diagnostics"
    echo "Model:    $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
    echo "Monitors: $(command -v hyprctl >/dev/null && hyprctl -j monitors 2>/dev/null | grep -o '"name": "[^"]*"' | tr '\n' ' ')"
    echo "Keyboard USB ($KBD_VENDOR:$KBD_PRODUCT): $(for d in /sys/bus/usb/devices/*; do [ -r "$d/idVendor" ] || continue; [ "$(cat "$d/idVendor")" = "$KBD_VENDOR" ] && [ "$(cat "$d/idProduct")" = "$KBD_PRODUCT" ] && echo present; done | head -1 || echo absent)"
    echo "Keyboard BT MAC: ${KBD_BT_MAC:-unset}"
    echo "Howdy: $(pacman -Qq howdy-next 2>/dev/null || echo not-installed)"
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        --check) do_check; exit 0 ;;
        --remove-faceid) remove_faceid; exit 0 ;;
        --force) FORCE=1 ;;
        "" ) ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac

    if [ "$FORCE" -ne 1 ] && ! is_zenbook_duo; then
        warn "This does not look like a Zenbook Duo ($(cat /sys/class/dmi/id/product_name 2>/dev/null))."
        ask_yn "Continue anyway?" n || exit 1
    fi

    load_config
    echo "Select components to set up:"
    ask_yn "  1) Dual-screen auto-toggle?" y && DO_SCREEN=1 || DO_SCREEN=0
    ask_yn "  2) Bluetooth keyboard auto-reconnect?" y && DO_KBD=1 || DO_KBD=0
    ask_yn "  3) Face unlock (Howdy)?" n && DO_FACE=1 || DO_FACE=0

    [ "$DO_SCREEN" = 1 ] && setup_screen
    [ "$DO_KBD" = 1 ] && setup_keyboard
    [ "$DO_FACE" = 1 ] && setup_faceid
    ok "Done. Run 'zenbook-duo-setup --check' anytime to inspect state."
}
main "$@"
```

- [ ] **Step 2:** `shellcheck bin/zenbook-duo-setup`.
- [ ] **Step 3:** Smoke: `bash bin/zenbook-duo-setup --help` (prints usage) and `bash bin/zenbook-duo-setup --check` (prints diagnostics, exit 0).
- [ ] **Step 4:** Commit `feat: zenbook-duo-setup orchestrator with menu/--check/--force`.

---

### Task 9: README (human voice)

**Files:**
- Create: `README.md`

- [ ] **Step 1:** Write README: what it is, supported hardware, install (`yay -S zenbook-duo-hyprland` once published; build-from-source meanwhile), `zenbook-duo-setup` walkthrough, each component explained, the bash gotcha note, troubleshooting (`--check`, `--remove-faceid`), uninstall. First-person, plain.
- [ ] **Step 2:** Commit `docs: README`.

---

### Task 10: PKGBUILD + .SRCINFO

**Files:**
- Create: `PKGBUILD`
- Create: `.SRCINFO`

- [ ] **Step 1:** Write PKGBUILD.

```bash
# Maintainer: Laith Masri <laith.masri@gmail.com>
pkgname=zenbook-duo-hyprland
pkgver=0.1.0
pkgrel=1
pkgdesc="Dual-screen auto-toggle, Bluetooth keyboard, and face unlock setup for ASUS Zenbook Duo on Hyprland"
arch=('any')
url="https://github.com/laithm/zenbook-duo-hyprland"
license=('MIT')
depends=('hyprland' 'bash' 'bluez-utils' 'systemd')
optdepends=('howdy-next: IR face unlock'
            'linux-enable-ir-emitter: enable the IR camera for Howdy')
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')

package() {
    cd "$srcdir/$pkgname-$pkgver"
    install -Dm755 bin/zenbook-duo-screen "$pkgdir/usr/bin/zenbook-duo-screen"
    install -Dm755 bin/zenbook-duo-setup  "$pkgdir/usr/bin/zenbook-duo-setup"
    install -Dm644 lib/common.sh   "$pkgdir/usr/lib/$pkgname/common.sh"
    install -Dm644 lib/screen.sh   "$pkgdir/usr/lib/$pkgname/screen.sh"
    install -Dm644 lib/keyboard.sh "$pkgdir/usr/lib/$pkgname/keyboard.sh"
    install -Dm644 lib/faceid.sh   "$pkgdir/usr/lib/$pkgname/faceid.sh"
    install -Dm644 share/exec-once.snippet "$pkgdir/usr/share/$pkgname/exec-once.snippet"
    install -Dm644 share/config.example    "$pkgdir/usr/share/$pkgname/config.example"
    install -Dm644 share/zenbook-duo-screen.service "$pkgdir/usr/share/$pkgname/zenbook-duo-screen.service"
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 LICENSE   "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
```

- [ ] **Step 2:** Build-test against the local tree (override source to use the working dir so it builds before any tag exists): copy tree into a temp build dir, run `makepkg -f --skipinteg` with a local `source`, confirm it produces `zenbook-duo-hyprland-0.1.0-1-any.pkg.tar.zst` and that `bsdtar -tf` lists the expected `/usr/bin` paths.
- [ ] **Step 3:** Generate `.SRCINFO`: `makepkg --printsrcinfo > .SRCINFO`.
- [ ] **Step 4:** Commit `feat: PKGBUILD and .SRCINFO`.

---

### Task 11: GitHub publish + tag + release

- [ ] **Step 1:** `gh repo create laithm/zenbook-duo-hyprland --public --source=. --remote=origin --description "..."` (or create then add remote); push `main`.
- [ ] **Step 2:** Tag: `git tag v0.1.0 && git push origin v0.1.0`.
- [ ] **Step 3:** `gh release create v0.1.0 --title "v0.1.0" --notes "..."`.
- [ ] **Step 4:** Fetch the release tarball, compute its real sha256, replace `SKIP` in PKGBUILD, regenerate `.SRCINFO`, commit `fix: pin release tarball sha256`, push.

---

### Task 12: AUR publish instructions (for the user)

**Files:**
- Create: `docs/PUBLISHING-AUR.md`

- [ ] **Step 1:** Write step-by-step: register SSH key at aur.archlinux.org, `git clone ssh://aur@aur.archlinux.org/zenbook-duo-hyprland.git`, copy `PKGBUILD` + `.SRCINFO`, commit, push. Note `.SRCINFO` must match `PKGBUILD`.
- [ ] **Step 2:** Commit `docs: AUR publishing guide`.

---

## Self-Review

- **Spec coverage:** screen daemon (T3/T5), BT keyboard (T6), Howdy + rollback (T7), interactive setup with guard/menu/--check (T8), config model (T2), templates incl. systemd unit (T4), PKGBUILD/optdepends/.SRCINFO (T10), GitHub+tag+release (T11), AUR steps (T12), README human voice + MIT/no-AI-trailer (T1/T9). All spec sections mapped.
- **Placeholders:** none; all scripts are complete.
- **Consistency:** `setup_screen`/`setup_keyboard`/`setup_faceid`/`remove_faceid` defined in lib, called in T8; config keys (`BOTTOM`, `ON_MODE`, `KBD_VENDOR`, `KBD_PRODUCT`, `KBD_BT_MAC`) consistent across common.sh, daemon, config.example, --check.
- **Note:** commits use plain conventional messages, authored as laithm, NO AI co-author trailer (repo policy).
