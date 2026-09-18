-- hyprtab keybinds for Hyprland 0.55+ (lua config)
--
-- Source this from your hyprland.lua:
--     dofile(os.getenv("HOME") .. "/.config/quickshell/hyprtab/hyprtab.lua")
--
-- For Hyprland 0.54 and older see hyprtab.conf (hyprlang syntax).

local mainMod = "SUPER"

-- Super+Tab: toggle the workspace overview.
-- exec_cmd keeps the hyprctl call off the compositor event loop.
hl.bind(mainMod .. " + TAB",
        hl.dsp.exec_cmd("qs ipc -c hyprtab call overview toggle"))

--------------------------------------------------------------------------
-- Alt+Tab MRU workspace switcher
--------------------------------------------------------------------------
-- These are GLOBAL SHORTCUTS, not dispatchers: Quickshell registers them
-- through hyprland-global-shortcuts-v1 and hyprtab receives them directly.
-- `hl.dsp.global("appid:name")` forwards the chord to the owning client.
--
-- The `mod` bind drives release-to-commit: hyprtab arms on the first Tab and
-- commits the switch when Alt comes back UP. The global shortcuts protocol
-- (hyprland-global-shortcuts-v1) sends BOTH a `pressed` and a `released`
-- event, and Quickshell's GlobalShortcut surfaces them as separate signals,
-- so one bind per key gives you both edges. No release flag needed.
--
-- NOTE THE MODIFIER IN THE CHORD: "ALT + Alt_L", not bare "Alt_L".
--
-- Pressing Alt_L means the ALT modifier is ALREADY held by the time the key
-- event is evaluated, so a bind with an empty modmask never matches and the
-- shortcut silently never fires -- no error, it just does nothing. Same
-- reason a Super launcher bind is written "SUPER + SUPER_L".
--
-- Symptom of getting this wrong: Alt+Tab opens the switcher (that's the
-- separate "ALT + Tab" bind) but releasing Alt never commits, and the quick
-- tap-and-release that should switch without showing the menu does nothing.
hl.bind("ALT + Alt_L", hl.dsp.global("hyprtab:mod"))
hl.bind("ALT + Alt_R", hl.dsp.global("hyprtab:mod"))

hl.bind("ALT + Tab",         hl.dsp.global("hyprtab:next"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("hyprtab:prev"))
hl.bind("ALT + Delete",      hl.dsp.global("hyprtab:closeAll"))
hl.bind("ALT + Escape",      hl.dsp.global("hyprtab:cancel"))

-- Escape and Delete also work as plain keys while the switcher is showing
-- (hyprtab holds keyboard focus), so these two binds are optional -- keep
-- them if you want them to work from the arm phase before the panel appears.
--
-- To check what registered, run:  hyprctl globalshortcuts
-- You should see hyprtab:mod, :next, :prev, :accept, :cancel, :closeAll

--------------------------------------------------------------------------
-- Optional: let Hyprland blur the hyprtab surfaces.
--------------------------------------------------------------------------
-- Set Config.altTabBackdropOpacity / overviewBackdropOpacity to 0 so the
-- full-screen dim layer doesn't sit on top of the blur.
hl.layer_rule({ match = { namespace = "hyprtab" },          blur = true })
hl.layer_rule({ match = { namespace = "hyprtab-overview" }, blur = true })
