#!/bin/bash

# File to store workspace history
HISTORY_FILE="/tmp/hypr_workspace_history_$$"
MAX_HISTORY=10

# Initialize with current workspace
CURRENT=$(hyprctl activeworkspace -j | jq '.id')
echo "$CURRENT" > "$HISTORY_FILE"

# Listen to workspace changes
hyprctl events -m workspace | while read -r event; do
    WS=$(echo "$event" | grep -oP '(?<=workspace>>)\d+')
    
    if [ -n "$WS" ]; then
        # Read current history
        HISTORY=$(cat "$HISTORY_FILE")
        
        # Remove if already in history (prevent duplicates)
        HISTORY=$(echo "$HISTORY" | grep -v "^$WS$")
        
        # Add new workspace to front
        HISTORY="$WS"$'\n'"$HISTORY"
        
        # Keep only last N entries
        HISTORY=$(echo "$HISTORY" | head -n $MAX_HISTORY)
        
        # Save back
        echo "$HISTORY" > "$HISTORY_FILE"
    fi
done
