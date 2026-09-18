-- monitors.lua
-- https://wiki.hypr.land/Configuring/Basics/Monitors/

---@module 'hl'

-- Catch-all: every output, preferred mode, auto position, scale 1
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Example explicit entry for the laptop panel, if you ever need to pin it:
-- hl.monitor({ output = "eDP-1", mode = "1920x1080@144.01", position = "0x0", scale = 1 })
