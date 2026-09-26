-- binds.lua
-- All keybindings.

---@module 'hl'

local v       = require("variables")
local mainMod = v.mainMod
local ipc     = v.ipc

-- Apps
hl.bind(mainMod .. " + Return",         hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + SHIFT + RETURN", hl.dsp.exec_cmd("[float; size 1200 675] kitty"))
hl.bind(mainMod .. " + E",              hl.dsp.exec_cmd("nautilus"))

-- Core Noctalia binds
hl.bind("SUPER + SUPER_L",       hl.dsp.exec_cmd(ipc .. " panel-toggle launcher"))
hl.bind(mainMod .. " + SPACE",   hl.dsp.exec_cmd(ipc .. " panel-toggle launcher"))
hl.bind(mainMod .. " + D",       hl.dsp.exec_cmd(ipc .. " panel-toggle control-center"))
hl.bind(mainMod .. " + I",       hl.dsp.exec_cmd(ipc .. " settings-open"))
hl.bind(mainMod .. " + V",       hl.dsp.exec_cmd(ipc .. " panel-toggle clipboard"))
hl.bind(mainMod .. " + PERIOD",  hl.dsp.exec_cmd(ipc .. " panel-toggle launcher/emo"))
hl.bind(mainMod .. " + ESCAPE",  hl.dsp.exec_cmd(ipc .. " panel-toggle session"))
hl.bind(mainMod .. " + L",       hl.dsp.exec_cmd(ipc .. " panel-toggle session"))
hl.bind(mainMod .. " + N",       hl.dsp.exec_cmd(ipc .. " panel-toggle control-center notifications"))
hl.bind(mainMod .. " + W",       hl.dsp.exec_cmd(ipc .. " panel-toggle wallpaper"))
hl.bind(mainMod .. " + SLASH",   hl.dsp.exec_cmd(ipc .. " panel-toggle kenn/keybind-cheatsheet:cheatsheet"))
hl.bind("XF86Launch2",           hl.dsp.exec_cmd(ipc .. " panel-toggle control-center system"))

-- snappy-switcher
hl.bind("ALT + Tab", hl.dsp.exec_cmd("snappy-switcher next --mod alt"), { description = "Snappy Switcher" })
-- hl.bind("SUPER + TAB", hl.dsp.exec_cmd("snappy-switcher next --workspace --mod super"))

-- hyprtab
-- hl.bind(mainMod .. " + TAB",    hl.dsp.exec_cmd("qs ipc -c hyprtab call overview toggle"))
-- hl.bind("ALT + Alt_L",          hl.dsp.global("hyprtab:mod"))
-- hl.bind("ALT + Alt_R",          hl.dsp.global("hyprtab:mod"))
-- hl.bind("ALT + Tab",            hl.dsp.global("hyprtab:next"))
-- hl.bind("ALT + SHIFT + Tab",    hl.dsp.global("hyprtab:prev"))
-- hl.bind("ALT + Delete",         hl.dsp.global("hyprtab:closeAll"))
-- hl.bind("ALT + Escape",         hl.dsp.global("hyprtab:cancel"))
-- hl.bind(mainMod .. " + SHIFT + TAB", hl.dsp.exec_cmd("qs ipc -c overview call overview toggle"))

-- Utility
hl.bind("PRINT",                                hl.dsp.exec_cmd("hyprshot -m region -z --no-cursor"))
hl.bind("SHIFT + PRINT",                        hl.dsp.exec_cmd("hyprshot -m region --raw | swappy -f -"))
hl.bind(mainMod .. " + PRINT",                  hl.dsp.exec_cmd("hyprshot -m output"))
hl.bind(mainMod .. " + SHIFT + PRINT",          hl.dsp.exec_cmd("hyprshot -m window"))
hl.bind(mainMod .. " + SHIFT + R",              hl.dsp.exec_cmd(ipc .. " plugin noctalia/screen_recorder:service all start portal"))
hl.bind("XF86Calculator",                       hl.dsp.exec_cmd("[float; size 400 800; pin] gnome-calculator"))
hl.bind(mainMod .. " + XF86Launch2",            hl.dsp.exec_cmd(v.home .. "/.local/bin/rice_flex.sh"))
hl.bind(mainMod .. " + SHIFT + XF86Launch2",    hl.dsp.exec_cmd(v.home .. "/.local/bin/rice_flex_2.sh"))
hl.bind("CTRL + ALT + DELETE",                  hl.dsp.exec_cmd(ipc .. " wallpaper-set " .. v.home .. "/Pictures/Wallpapers/cooked.png && notify-send -u critical \"FAHHHHH\""))
-- hl.bind("SUPER + ALT + space",                  hl.dsp.exec_cmd("fcitx5-remote -t"))  -- keyboard language switch

-- Media keys
hl.bind("XF86AudioRaiseVolume",     hl.dsp.exec_cmd(ipc .. " volume-up 5"),    { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume",     hl.dsp.exec_cmd(ipc .. " volume-down 5"),  { repeating = true, locked = true })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.exec_cmd(ipc .. " volume-up 1"))
hl.bind(mainMod .. " + mouse_down", hl.dsp.exec_cmd(ipc .. " volume-down 1"))
hl.bind("XF86AudioMute",            hl.dsp.exec_cmd(ipc .. " volume-mute"),    { locked = true })
hl.bind("ALT + M",                  hl.dsp.exec_cmd(ipc .. " mic-mute"),       { locked = true })
hl.bind("XF86MonBrightnessUp",      hl.dsp.exec_cmd(ipc .. " brightness-up"),  { repeating = true, locked = true })
hl.bind("XF86MonBrightnessDown",    hl.dsp.exec_cmd(ipc .. " brightness-down"), { repeating = true, locked = true })
hl.bind("XF86AudioPlay",            hl.dsp.exec_cmd(ipc .. " media toggle"),   { locked = true })
hl.bind("XF86AudioPause",           hl.dsp.exec_cmd(ipc .. " media toggle"),   { locked = true })
hl.bind("XF86AudioNext",            hl.dsp.exec_cmd(ipc .. " media next"),     { locked = true })
hl.bind("XF86AudioPrev",            hl.dsp.exec_cmd(ipc .. " media previous"), { locked = true })

-- Window management
hl.bind(mainMod .. " + Q",              hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + space",  hl.dsp.window.float())
hl.bind(mainMod .. " + F",              hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + Left",           hl.dsp.focus({ direction = "left"  }))
hl.bind(mainMod .. " + Down",           hl.dsp.focus({ direction = "down"  }))
hl.bind(mainMod .. " + Up",             hl.dsp.focus({ direction = "up"    }))
hl.bind(mainMod .. " + Right",          hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + Left",   hl.dsp.window.move({ direction = "left"  }))
hl.bind(mainMod .. " + SHIFT + Down",   hl.dsp.window.move({ direction = "down"  }))
hl.bind(mainMod .. " + SHIFT + Up",     hl.dsp.window.move({ direction = "up"    }))
hl.bind(mainMod .. " + SHIFT + Right",  hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + CTRL + Left",    hl.dsp.window.resize({ x = -20, y =   0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + Right",   hl.dsp.window.resize({ x =  20, y =   0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + Up",      hl.dsp.window.resize({ x =   0, y = -20, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + Down",    hl.dsp.window.resize({ x =   0, y =  20, relative = true }), { repeating = true })
-- hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
-- hl.bind(mainMod .. " + J", hl.dsp.window.toggle_split())

-- Switch workspaces: mainMod + [0-9]
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
end
hl.bind(mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

-- Move active window to workspace: mainMod + SHIFT + [0-9]
for i = 1, 9 do
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through workspaces
-- hl.bind(mainMod .. " + mouse_up",   hl.dsp.workspace.relative(1))
-- hl.bind(mainMod .. " + mouse_down", hl.dsp.workspace.relative(-1))

-- Move/resize with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
