#!/usr/bin/env bash
# ~/.local/bin/gamemode-toggle.sh  (noctalia v5)
STATE="${XDG_RUNTIME_DIR:-/tmp}/gamemode.on"
PREV="${XDG_RUNTIME_DIR:-/tmp}/gamemode.prevprofile"
N="noctalia msg"
notify() { notify-send -u low -t 2000 "Game mode" "$1" 2>/dev/null; }

if [ ! -e "$STATE" ]; then
    touch "$STATE"
    notify "On"
    powerprofilesctl get > "$PREV" 2>/dev/null
    $N power-set performance
    $N desktop-widgets-hide
    $N caffeine-enable              # no screen idle/lock while gaming
    $N notification-dnd-set true    # no popups over the game
    hyprctl eval 'hl.config({
        animations = { enabled = false },
        general    = { gaps_in = 0, gaps_out = 0, border_size = 1 },
        decoration = { rounding = 0, dim_inactive = false,
                       blur = { enabled = false }, shadow = { enabled = false } },
    })'
else
    rm -f "$STATE"
    hyprctl reload
    $N desktop-widgets-show
    $N caffeine-disable
    $N notification-dnd-set false
    [ -s "$PREV" ] && $N power-set "$(cat "$PREV")"
    rm -f "$PREV"
    notify "Off"
fi
