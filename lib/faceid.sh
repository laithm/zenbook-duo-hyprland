#!/usr/bin/env bash
# Optional Howdy IR face unlock. Installs the dependencies on request, applies
# the workaround=off fix, enrolls a face, and only then wires pam_howdy into
# the chosen PAM services. Every PAM file it edits is backed up first, and a
# successful enrollment + test is required before any PAM change is made.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"

PAM_LINE="auth sufficient pam_howdy.so"
BAK_SUFFIX=".zenbook-duo.bak"

ensure_deps() {
    pacman -Qq howdy-next >/dev/null 2>&1 && return 0
    local h
    h=$(aur_helper) || { err "No AUR helper (yay/paru) found; install howdy-next manually."; return 1; }
    ask_yn "Install howdy-next + linux-enable-ir-emitter via $h?" y || return 1
    "$h" -S --needed howdy-next linux-enable-ir-emitter
}

# wire_pam /etc/pam.d/<service> -- prepend the howdy line, backing up first.
wire_pam() {
    local f="$1"
    [ -f "$f" ] || { warn "$f missing, skipping."; return; }
    if grep -q pam_howdy "$f"; then
        ok "$f already has howdy."
        return
    fi
    sudo cp -n "$f" "${f}${BAK_SUFFIX}"
    sudo sed -i "1i $PAM_LINE" "$f"
    ok "Added howdy to $f (backup: ${f}${BAK_SUFFIX})"
}

setup_faceid() {
    msg "Configuring Howdy face unlock"
    ensure_deps || return 1

    # The documented gotcha on this hardware: pam_howdy needs workaround=off.
    if [ -f /etc/howdy/config.ini ]; then
        sudo sed -i 's/^[[:space:]]*workaround[[:space:]]*=.*/workaround = off/' /etc/howdy/config.ini
        ok "Set workaround=off in /etc/howdy/config.ini"
    fi

    msg "Configuring the IR emitter (this may prompt you)."
    if command -v linux-enable-ir-emitter >/dev/null; then
        sudo linux-enable-ir-emitter configure || warn "IR emitter config did not complete; fix it if face detection fails."
    else
        warn "linux-enable-ir-emitter not installed; the IR camera may not work."
    fi

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
            sudo mv "${f}${BAK_SUFFIX}" "$f"
            ok "Restored $f from backup"
        elif grep -q pam_howdy "$f" 2>/dev/null; then
            sudo sed -i '/pam_howdy/d' "$f"
            ok "Stripped howdy line from $f"
        fi
    done
    ok "Done. Howdy itself is left installed; remove it with your AUR helper if you want."
}
