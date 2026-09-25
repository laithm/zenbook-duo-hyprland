#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"

HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
MAIN_CONF="$HYPR_DIR/hyprland.conf"
USERPREFS="$HYPR_DIR/userprefs.conf"
BEGIN="# >>> zenbook-duo-hyprland >>>"
END="# <<< zenbook-duo-hyprland <<<"

snippet_path() {
    local path

    for path in \
        /usr/share/zenbook-duo-hyprland/exec-once.snippet \
        "$HERE/../share/exec-once.snippet"
    do
        [ -r "$path" ] && {
            echo "$path"
            return 0
        }
    done

    return 1
}

hypr_config_target() {
    if [ -f "$USERPREFS" ] &&
        [ -r "$MAIN_CONF" ] &&
        grep -Eq '^[[:space:]]*source[[:space:]]*=[[:space:]]*.*userprefs\.conf' "$MAIN_CONF"
    then
        echo "$USERPREFS"
    else
        echo "$MAIN_CONF"
    fi
}

setup_screen() {
    msg "Configuring dual-screen auto-toggle"

    local snippet target
    snippet="$(snippet_path)" || {
        err "exec-once snippet not found."
        return 1
    }

    target="$(hypr_config_target)"
    mkdir -p "$(dirname "$target")"
    touch "$target"

    sed -i "/$BEGIN/,/$END/d" "$target"
    printf '\n%s\n' "$(cat "$snippet")" >> "$target"

    ok "Added zenbook-duo-screen to $target"
    msg "Restart Hyprland to activate it, or run zenbook-duo-screen now."
}
