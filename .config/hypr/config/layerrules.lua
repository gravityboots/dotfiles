-- layerrules.lua
-- One line per rule. blur + ignore_alpha for the same namespace are merged.

---@module 'hl'

-- Noctalia
-- Matching noctalia-.*$ works but causes some border aliasing issues.
hl.layer_rule({ name = "noctalia", match = { namespace = "noctalia-background-.*$" }, ignore_alpha = 0, blur = true, blur_popups = true })
hl.layer_rule({ match = { namespace = "noctalia-shell:regionSelector" }, no_anim = true })

-- Noctalia v5 namespaces (uncomment once on v5; replaces the two lines above)
-- hl.layer_rule({ name = "noctalia", match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$" }, no_anim = true, ignore_alpha = 0.5, blur = true, blur_popups = true })

-- Quickshell
hl.layer_rule({ match = { namespace = "quickshell" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:overview" }, blur = true, ignore_alpha = 0 })

-- hyprtab
hl.layer_rule({ match = { namespace = "hyprtab" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "hyprtab-overview" }, blur = true, ignore_alpha = 0 })

-- Legacy (waybar / swaync) -- kept from the old setup, safe to delete
hl.layer_rule({ match = { namespace = "waybar" },                     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "swaync-control-center" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "swaync-notification-window" }, blur = true, ignore_alpha = 0 })

-- Fix for hyprshot region-select screenshots
hl.layer_rule({ match = { namespace = "selection" },  no_anim = true })
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true })
