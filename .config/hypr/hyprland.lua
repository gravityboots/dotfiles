-- ~/.config/hypr/hyprland.lua
-- Entry point. Hyprland loads this INSTEAD of hyprland.conf when it exists.
-- To roll back: rename this file and restart Hyprland.

---@module 'hl'

package.path = os.getenv("HOME") .. "/.config/hypr/config/?.lua;" .. package.path
hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow") -- allow hyprpm

require("variables")      -- mainMod, ipc, paths (must be first)
require("monitors")
require("environment")
require("appearance")     -- general, decoration, animations
require("input")          -- input, dwindle, misc, cursor
require("binds")
require("windowrules")
require("layerrules")
require("autostart")      -- last: start things after config is applied
