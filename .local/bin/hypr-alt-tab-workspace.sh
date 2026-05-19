#!/bin/bash

HISTORY_FILE="/tmp/hypr_workspace_history_$$"
DIRECTION="${1:-forward}"  # forward or backward

if [ ! -f "$HISTORY_FILE" ]; then
    echo "History file not found. Make sure the daemon is running."
    exit 1
fi

if [ "$DIRECTION" = "backward" ]; then
    # For backward (Shift+Tab), cycle through history in reverse order
    # Get the last workspace in history instead of second
    NEXT_WS=$(tail -n 1 "$HISTORY_FILE")
else
    # For forward (Tab), get second workspace in history
    NEXT_WS=$(sed -n '2p' "$HISTORY_FILE")
fi

if [ -n "$NEXT_WS" ]; then
    hyprctl dispatch workspace "$NEXT_WS"
fi
