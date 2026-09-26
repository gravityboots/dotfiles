-- appearance.lua
-- general, decoration, animations

---@module 'hl'

hl.config({
    general = {
        layout      = "dwindle",
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 0,
        ["col.active_border"]   = "rgba(0a0b0fd9)", -- alts: rgb(414868), rgb(c0caf5), rgb(585b70)
        ["col.inactive_border"] = "rgba(0a0b0fd9)", -- alts: rgb(414868), rgb(2a2b36)
    },

    decoration = { -- keep border radius 21 & rounding power 3 for no aliasing on 1920x1080, with border_size=0
        rounding        = 21,
        rounding_power  = 3.0,   -- 2 = regular circle, higher = more squircle-ish
        active_opacity   = 1,
        inactive_opacity = 1,
        dim_inactive     = true,
        dim_strength     = 0.04,
        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = "rgba(1a1a1aee)",  -- alt: rgba(00000040)
            -- offset    = { 0, 6 },
        },
        blur = {
            enabled           = true,
            size              = 8,
            passes            = 3,
            ignore_opacity    = true,
            new_optimizations = true,
            special           = true,
            popups            = true,
            xray              = false,
            vibrancy          = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})


-- Bezier curves
hl.curve("bounce",  { type = "bezier", points = { { 0.0, 1.25 }, { 0.15, 1.0  } } })
hl.curve("buttery", { type = "bezier", points = { { 0.1, 1.15 }, { 0.15, 1.02 } } })
hl.curve("smooth",  { type = "bezier", points = { { 0.0, 0.0  }, { 0.12, 1.0  } } })
hl.curve("linear",  { type = "bezier", points = { { 0.0, 0.0  }, { 1.0,  1.0  } } })

-- Animations
hl.animation({ leaf = "windowsIn",        enabled = true, speed = 4.5, bezier = "bounce",  style = "slide" })
hl.animation({ leaf = "windowsOut",       enabled = true, speed = 3.5, bezier = "smooth",  style = "slide" })
hl.animation({ leaf = "windowsMove",      enabled = true, speed = 4,   bezier = "buttery", style = "slide" })
hl.animation({ leaf = "fadeIn",           enabled = true, speed = 3.5, bezier = "smooth"  })
hl.animation({ leaf = "fadeOut",          enabled = true, speed = 3,   bezier = "smooth"  })
hl.animation({ leaf = "fadeDim",          enabled = true, speed = 4,   bezier = "smooth"  })
hl.animation({ leaf = "fadeShadow",       enabled = true, speed = 4,   bezier = "smooth"  })
hl.animation({ leaf = "workspaces",       enabled = true, speed = 4.5, bezier = "buttery", style = "slidefade 10%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4.5, bezier = "buttery", style = "slidefadevert -15%" })
hl.animation({ leaf = "border",           enabled = true, speed = 7,   bezier = "smooth"  })
hl.animation({ leaf = "borderangle",      enabled = true, speed = 35,  bezier = "linear",  style = "loop" })
hl.animation({ leaf = "layersIn",         enabled = true, speed = 4,   bezier = "bounce",  style = "slide" })
hl.animation({ leaf = "layersOut",        enabled = true, speed = 3,   bezier = "smooth",  style = "slide" })
