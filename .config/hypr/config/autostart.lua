-- autostart.lua
-- Replaces exec-once. Runs on the hyprland.start event.

---@module 'hl'

hl.on("hyprland.start", function()
    -- Shell
    hl.exec_cmd("noctalia")
    hl.exec_cmd("snappy-switcher --daemon")

    -- Keyring / polkit
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")

    -- Environment propagation to systemd / D-Bus
    hl.exec_cmd("dbus-update-activation-environment --systemd SSH_AUTH_SOCK")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Services
    hl.exec_cmd("fcitx5 -d")

    -- Loop until IPC is ready, then reload hyprpm & disable gamemode noctalia bar
    hl.exec_cmd("sh -c 'for i in $(seq 1 20); do hyprctl -j monitors >/dev/null 2>&1 && break; sleep 0.25; done; hyprpm reload -n'")
    hl.exec_cmd("sh -c 'sleep 1; noctalia msg bar-hide gamemode'")
end)
