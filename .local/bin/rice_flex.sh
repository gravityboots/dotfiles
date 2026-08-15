#!/bin/bash
# export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:$HOME/.local/bin:$PATH"
# hyprctl dispatch layoutmsg preselect r
# hyprctl dispatch movefocus r

hyprctl dispatch movecursor 1920 1080
sleep 0.2
hyprctl dispatch exec "kitty --hold -e btop"
hyprctl dispatch exec "kitty --hold -e fastfetch"
sleep 0.2
hyprctl dispatch resizewindowpixel 100 0, activewindow
hyprctl dispatch exec "kitty --hold -e cmatrix"
sleep 0.2
hyprctl dispatch resizewindowpixel 0 40, activewindow
hyprctl dispatch exec "kitty --hold"
sleep 0.2
hyprctl dispatch resizewindowpixel 40 0, activewindow
