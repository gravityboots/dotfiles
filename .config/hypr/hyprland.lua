-- ~/.config/hypr/hyprland.lua
-- Entry point. Hyprland loads this INSTEAD of hyprland.conf when it exists.
-- To roll back: rename this file and restart Hyprland.

---@module 'hl'

package.path = os.getenv("HOME") .. "/.config/hypr/config/?.lua;" .. package.path
require("variables")      -- mainMod, ipc, paths (must be first)
require("monitors")
require("environment")
require("appearance")     -- general, decoration, animations
require("layout")         -- scrolling, dwindle, etc.
require("input")          -- input, misc, cursor
require("binds")
require("plugins")
require("windowrules")
require("layerrules")
require("autostart")      -- last: start things after config is applied
