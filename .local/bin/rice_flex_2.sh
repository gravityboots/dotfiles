#!/bin/bash
# export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:$HOME/.local/bin:$PATH"
# hyprctl dispatch layoutmsg preselect r
# hyprctl dispatch movefocus r

hyprctl dispatch movecursor 1920 1080

hyprctl dispatch exec "kitty -e btop"

hyprctl dispatch exec "kitty --hold -e nitch"

hyprctl dispatch exec "kitty -e cmatrix"
sleep 0.2
hyprctl dispatch resizewindowpixel 0 100, activewindow
