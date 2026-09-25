#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"

PAM_LINE="auth sufficient pam_howdy.so"
BAK_SUFFIX=".zenbook-duo.bak"

ensure_deps() {
    local missing=() helper

    pacman -Qq howdy-next >/dev/null 2>&1 ||
        missing+=(howdy-next)
    pacman -Qq linux-enable-ir-emitter >/dev/null 2>&1 ||
        missing+=(linux-enable-ir-emitter)

    [ "${#missing[@]}" -eq 0 ] && return 0

    helper=$(aur_helper) || {
        err "Install ${missing[*]} manually, or install yay/paru first."
        return 1
    }

    ask_yn "Install ${missing[*]} via $helper?" y || return 1
    "$helper" -S --needed "${missing[@]}"
}

wire_pam() {
    local file="$1"

    [ -f "$file" ] || {
        warn "$file is missing; skipping it."
        return
    }

    if grep -q pam_howdy "$file"; then
        ok "$file already has Howdy enabled."
        return
    fi

    sudo cp -n "$file" "${file}${BAK_SUFFIX}"
    sudo sed -i "1i $PAM_LINE" "$file"
    ok "Added Howdy to $file"
}

setup_faceid() {
    msg "Configuring Howdy face unlock"
    ensure_deps || return 1

    if [ -f /etc/howdy/config.ini ]; then
        sudo sed -i \
            's/^[[:space:]]*workaround[[:space:]]*=.*/workaround = off/' \
            /etc/howdy/config.ini
        ok "Set workaround=off in /etc/howdy/config.ini"
    fi

    if command -v linux-enable-ir-emitter >/dev/null; then
        msg "Configuring the IR emitter."
        sudo linux-enable-ir-emitter configure ||
            warn "IR emitter setup did not finish; face detection may need manual setup."
    fi

    msg "Enroll your face now."
    sudo howdy add || {
        err "Enrollment failed; PAM was not changed."
        return 1
    }

    if ! sudo howdy test; then
        err "howdy test failed; PAM was not changed."
        return 1
    fi

    wire_pam /etc/pam.d/sudo
    wire_pam /etc/pam.d/hyprlock

    if ask_yn "Also enable face unlock at the SDDM login screen?" n; then
        wire_pam /etc/pam.d/sddm
    fi

    ok "Face unlock configured. Test it with: sudo -k; sudo true"
}

remove_faceid() {
    msg "Removing Howdy PAM integration"

    local file
    for file in /etc/pam.d/sudo /etc/pam.d/hyprlock /etc/pam.d/sddm; do
        if [ -f "${file}${BAK_SUFFIX}" ]; then
            sudo mv "${file}${BAK_SUFFIX}" "$file"
            ok "Restored $file from backup"
        elif grep -q pam_howdy "$file" 2>/dev/null; then
            sudo sed -i '/pam_howdy/d' "$file"
            ok "Removed Howdy from $file"
        fi
    done

    ok "Howdy itself was left installed."
}
