#!/usr/bin/env bash
# Shared helpers for the zenbook-duo-hyprland setup steps. Sourced by
# zenbook-duo-setup and the individual step scripts.

ZD_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zenbook-duo"
ZD_CONFIG="$ZD_CONFIG_DIR/config"

# Baked-in defaults for a stock UX8406. The config file can override any of
# these; only KBD_BT_MAC is genuinely per-unit.
: "${BOTTOM:=eDP-2}"
: "${ON_MODE:=preferred,0x900,2}"
: "${KBD_VENDOR:=0b05}"
: "${KBD_PRODUCT:=1b2c}"
: "${KBD_BT_MAC:=}"

msg()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m xx\033[0m %s\n' "$*" >&2; }

# ask_yn "prompt" [default y|n] -> exit 0 for yes, 1 for no
ask_yn() {
    local prompt="$1" def="${2:-n}" ans hint="[y/N]"
    [ "$def" = y ] && hint="[Y/n]"
    read -r -p "$prompt $hint " ans
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[Yy] ]]
}

load_config() {
    # shellcheck source=/dev/null
    [ -r "$ZD_CONFIG" ] && . "$ZD_CONFIG"
}

# save_config_kv KEY VALUE -- idempotent upsert into the config file.
save_config_kv() {
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

# Print the first available AUR helper, or return 1 if none.
aur_helper() {
    local h
    for h in yay paru; do
        command -v "$h" >/dev/null && { echo "$h"; return 0; }
    done
    return 1
}
