#!/usr/bin/env bash
# Enable the screen auto-toggle daemon by adding a managed exec-once block to
# the user's Hyprland config. Idempotent: it rewrites the block rather than
# appending a duplicate.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"

USERPREFS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/userprefs.conf"
BEGIN="# >>> zenbook-duo-hyprland >>>"
END="# <<< zenbook-duo-hyprland <<<"

# Resolve the installed snippet, falling back to the repo copy for dev runs.
snippet_path() {
    local p
    for p in /usr/share/zenbook-duo-hyprland/exec-once.snippet "$HERE/../share/exec-once.snippet"; do
        [ -r "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

setup_screen() {
    msg "Configuring dual-screen auto-toggle"
    local snippet
    snippet="$(snippet_path)" || { err "exec-once snippet not found."; return 1; }

    if [ ! -f "$USERPREFS" ]; then
        warn "No $USERPREFS found; creating it."
        mkdir -p "$(dirname "$USERPREFS")"
        touch "$USERPREFS"
    fi

    # Drop any existing managed block, then append a fresh one.
    sed -i "/$BEGIN/,/$END/d" "$USERPREFS"
    printf '\n%s\n' "$(cat "$snippet")" >> "$USERPREFS"
    ok "exec-once block written to $USERPREFS"
    msg "Restart Hyprland to activate (or run zenbook-duo-screen now)."
}
