-- windowrules.lua
-- One line per rule. Properties for the same class are merged into a single rule.

---@module 'hl'

-- Global
hl.window_rule({ match = { float = true },          center = true })
hl.window_rule({ match = { class = "^(fcitx)$" },   float  = true })
hl.window_rule({ match = { class = "kitty" },       min_size = { 100, 100 } })

-- Float + center + size (+ opacity)
hl.window_rule({ match = { class = "dev.noctalia.Noctalia" },                   float = true, center = true, size = { 1200, 900 } })
hl.window_rule({ match = { class = "^(org.gnome.Calculator)$" },                float = true, center = true, size = { 400, 800 }, opacity = "1.0 0.5" })
hl.window_rule({ match = { class = "md.obsidian.Obsidian" },                    float = true, center = true, size = { 1600, 900 }, opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "^(org.prismlauncher.PrismLauncher)$" },     float = true, center = true, size = { 1600, 900 }, opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "localsend" },                               float = true, center = true, size = { 1600, 900 }, opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "soundux" },                                 float = true, center = true, size = { 1600, 900 } })

-- Opacity only
hl.window_rule({ match = { class = "^(Spotify)$" },            opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "^(vesktop)$" },            opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "^(Termius)$" },            opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "codium" },                 opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "^(org.gnome.Nautilus)$" }, opacity = "0.90 0.90" })

-- Float + center (viewers)
hl.window_rule({ match = { class = "^(org.gnome.Evince)$" },    float = true, center = true })
hl.window_rule({ match = { class = "^(previewer)$" },           float = true, center = true })
hl.window_rule({ match = { class = "^(org.gnome.Showtime)$" },  float = true, center = true })
hl.window_rule({ match = { class = "^(org.gnome.Loupe)$" },     float = true, center = true })
hl.window_rule({ match = { class = "^(org.gnome.Decibels)$" },  float = true, center = true })