-- layout.lua
-- scrolling, dwindle, etc.

---@module 'hl'

hl.config({
    general = {
        layout = "scrolling", -- default "dwindle"
    },

    dwindle = {
        preserve_split = true,
    },

    scrolling = {
        column_width = 1,
        direction = "right",
        fullscreen_on_one_column = true,
        focus_fit_method = 1,
        explicit_column_widths = "0.333, 0.5, 0.667, 1.0",
        follow_focus = true,
    },

    master = {
        new_status = "master",
    },

    scrolling = {
        fullscreen_on_one_column = true,
    },
})