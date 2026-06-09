#!/usr/bin/env bash
# Pair / bond / trust the detachable keyboard over Bluetooth so it
# auto-reconnects on every detach. If it is already bonded, just make sure it
# is trusted and record its MAC.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"

# Look through already-bonded devices for one that looks like the keyboard.
find_known_kbd() {
    local mac name
    while read -r _ mac _; do
        [ -n "$mac" ] || continue
        name=$(bluetoothctl info "$mac" 2>/dev/null | sed -n 's/^[[:space:]]*Name: //p')
        case "$name" in
            *Keyboard*|*keyboard*|*ZenBook*|*Zenbook*) echo "$mac"; return 0 ;;
        esac
    done < <(bluetoothctl devices Bonded 2>/dev/null)
    return 1
}

setup_keyboard() {
    msg "Configuring Bluetooth keyboard"
    command -v bluetoothctl >/dev/null || { err "bluez-utils not installed."; return 1; }
    bluetoothctl power on >/dev/null 2>&1

    local mac
    if mac=$(find_known_kbd); then
        ok "Found bonded keyboard: $mac"
    else
        warn "No bonded keyboard found yet."
        echo "Detach the keyboard now so it advertises over Bluetooth."
        ask_yn "Scan and pair now?" y || { warn "Skipped keyboard setup."; return 0; }
        bluetoothctl --timeout 20 scan on >/dev/null 2>&1
        echo "Devices seen:"
        bluetoothctl devices
        read -r -p "Enter the keyboard's MAC (AA:BB:CC:DD:EE:FF): " mac
        [ -n "$mac" ] || { err "No MAC entered."; return 1; }
        bluetoothctl pair "$mac"
    fi

    bluetoothctl trust "$mac" >/dev/null 2>&1
    bluetoothctl connect "$mac" >/dev/null 2>&1 || true
    save_config_kv KBD_BT_MAC "$mac"
    ok "Keyboard $mac trusted and saved. It will auto-reconnect on detach."
}
