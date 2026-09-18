-- windowrules.lua
-- One line per rule. Properties for the same class are merged into a single rule.

---@module 'hl'

-- Global
hl.window_rule({ match = { float = true },            center = true })
hl.window_rule({ match = { class = "^(fcitx)$" },     float  = true })
-- hl.window_rule({ match = { class = "kitty" }, min_size = { 100, 100 } })

-- Noctalia v5 settings window (uncomment once on v5)
hl.window_rule({ match = { class = "dev.noctalia.Noctalia" }, float = true, size = { 1200, 900 } })

-- Opacity only
hl.window_rule({ match = { class = "^(Spotify)$" },            opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "^(vesktop)$" },            opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "^(Termius)$" },            opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "codium" },                 opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "obsidian" },               opacity = "0.90 0.90" })
hl.window_rule({ match = { class = "^(org.gnome.Nautilus)$" }, opacity = "0.90 0.90" })

-- Float + center (viewers)
hl.window_rule({ match = { class = "^(org.gnome.Evince)$" },    float = true, center = true })
-- hl.window_rule({ match = { class = "^(org.gnome.Evince)$" },    size = { 1600, 900 } })

hl.window_rule({ match = { class = "^(previewer)$" },           float = true, center = true })
-- hl.window_rule({ match = { class = "^(previewer)$" },           size = { 1600, 900 } })

hl.window_rule({ match = { class = "^(org.gnome.Showtime)$" },  float = true, center = true })
-- hl.window_rule({ match = { class = "^(org.gnome.Showtime)$" },  size = { 1600, 900 } })

hl.window_rule({ match = { class = "^(org.gnome.Loupe)$" },     float = true, center = true })
-- hl.window_rule({ match = { class = "^(org.gnome.Loupe)$" },     size = { 1600, 900 } })

hl.window_rule({ match = { class = "^(org.gnome.Decibels)$" },  float = true, center = true })
-- hl.window_rule({ match = { class = "^(org.gnome.Decibels)$" },  size = { 800, 400 } })

-- Float + center + size (+ opacity)
hl.window_rule({ match = { class = "^(org.gnome.Calculator)$" },            float = true, center = true, size = { 400, 800 },   opacity = "1.0 0.5" })
hl.window_rule({ match = { class = "^(org.prismlauncher.PrismLauncher)$" }, float = true, center = true, size = { 1600, 900 }, opacity = "0.85 0.85" })
hl.window_rule({ match = { class = "mpv" },                                 float = true, center = true, size = { 1600, 900 }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "scratchterm" },                        float = true, center = true, size = { "85%", "70%" } })
hl.window_rule({ match = { class = "localsend" },                          float = true, center = true, size = { 1600, 900 } })
-- hl.window_rule({ match = { class = "soundux" },                            float = true, center = true, size = { 1600, 900 } })
-- hl.window_rule({ match = { class = "^(termius)$" },  })  -- was incomplete in the old config
