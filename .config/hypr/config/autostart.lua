-- autostart.lua
-- Replaces exec-once. Runs on the hyprland.start event.

---@module 'hl'

hl.on("hyprland.start", function()
    -- Shell
    hl.exec_cmd("noctalia")
    hl.exec_cmd("qs -c hyprtab")

    -- Keyring / polkit
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Environment propagation to systemd / D-Bus
    hl.exec_cmd("dbus-update-activation-environment --systemd SSH_AUTH_SOCK")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Services
    hl.exec_cmd("mpd-mpris")
    hl.exec_cmd("fcitx5 -d")
    -- hl.exec_cmd("victus-control")
end)
