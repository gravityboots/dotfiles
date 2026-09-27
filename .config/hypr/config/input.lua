-- input.lua
-- input, misc, cursor

---@module 'hl'

hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        sensitivity  = 0,      -- -1.0 to 1.0, 0 = no modification
        scroll_factor = 0.5,
        touchpad = {
            natural_scroll = true,
            tap_to_click   = true,
            scroll_factor  = 0.75,
        },
    },

    misc = {
        disable_hyprland_logo        = true,
        animate_manual_resizes       = true,
        animate_mouse_windowdragging = true,
        vrr                          = 1,
        mouse_move_enables_dpms      = true,
        key_press_enables_dpms       = true,
        -- vfr = true,  -- from the Hyprland wiki performance section; errored on 0.55.1
    },

    cursor = {
        inactive_timeout = 3,
    },
})
