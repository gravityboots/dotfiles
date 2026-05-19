#!/bin/bash

# Configuration
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Timestamp
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
FILENAME="Screenshot_$TIMESTAMP.png"
FILEPATH="$SCREENSHOT_DIR/$FILENAME"

# Function to send notification
notify_screenshot() {
    local status=$1
    local message=$2
    local filepath=$3
    
    if command -v notify-send &> /dev/null; then
        if [ "$status" = "success" ]; then
            notify-send -i screenshot "Screenshot saved" "$message" -t 3000
            # Optional: show thumbnail preview
            # notify-send -i "$filepath" "Screenshot" "$filepath"
        else
            notify-send -i error "Screenshot failed" "$message" -u critical -t 5000
        fi
    fi
}

# Take screenshot based on mode
case "$1" in
    window)
        grim -g "$(hyprctl activewindow -j | jq -r '.at,.size | @csv' | sed 's/,/ /' | tr ',' ' ')" "$FILEPATH"
        ;;
    region)
        # Use slurp for region selection
        REGION=$(slurp -b "rgba(0, 0, 0, 0.3)" -c "rgb(100, 200, 255)" -w 2)
        if [ -z "$REGION" ]; then
            notify_screenshot "error" "Screenshot cancelled"
            exit 1
        fi
        grim -g "$REGION" "$FILEPATH"
        ;;
    output)
        # Get current monitor
        MONITOR=$(hyprctl activemonitor -j | jq -r '.name')
        grim -o "$MONITOR" "$FILEPATH"
        ;;
    *)
        notify_screenshot "error" "Invalid mode: $1"
        exit 1
        ;;
esac

# Check if screenshot was successful
if [ $? -eq 0 ] && [ -f "$FILEPATH" ]; then
    # Copy to clipboard
    wl-copy < "$FILEPATH"
    
    # Notify success
    notify_screenshot "success" "Saved to $SCREENSHOT_DIR\n(Also copied to clipboard)"
    
    # Optional: Open in image viewer
    # swaymsg exec "swayimg $FILEPATH"
else
    notify_screenshot "error" "Failed to take screenshot"
    exit 1
fi
