# hyprtab

Alt+Tab MRU workspace switcher and Super+Tab workspace overview for Hyprland,
with **live** window previews (wayland screencopy), drag-and-drop between
workspaces, special-workspace support, and Noctalia theme integration.

Built as a standalone [Quickshell](https://quickshell.org) config.

---

## Install

```sh
git clone <this> ~/.config/quickshell/hyprtab
qs -c hyprtab          # run in foreground to see logs
```

To autostart, add to your Hyprland config:

```lua
-- hyprland.lua (0.55+)
hl.on("hyprland.start", function()
  hl.dispatch(hl.dsp.exec_cmd("qs -c hyprtab"))
end)
```

---

## Keybinds

### Hyprland 0.55+ (lua config)

Hyprland 0.55 deprecated hyprlang in favour of lua. Source the bundled file
from your `~/.config/hypr/hyprland.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/quickshell/hyprtab/hyprtab.lua")
```

Or paste the binds inline:

```lua
local mainMod = "SUPER"

-- Super+Tab: workspace overview
hl.bind(mainMod .. " + TAB",
        hl.dsp.exec_cmd("qs ipc -c hyprtab call overview toggle"))

-- Alt+Tab MRU switcher (global shortcuts, forwarded to hyprtab)
hl.bind("ALT + Alt_L",       hl.dsp.global("hyprtab:mod"))
hl.bind("ALT + Alt_R",       hl.dsp.global("hyprtab:mod"))
hl.bind("ALT + Tab",         hl.dsp.global("hyprtab:next"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("hyprtab:prev"))
hl.bind("ALT + Delete",      hl.dsp.global("hyprtab:closeAll"))
hl.bind("ALT + Escape",      hl.dsp.global("hyprtab:cancel"))
```

**Write the modifier binds as `"ALT + Alt_L"`, not bare `"Alt_L"`.**
Pressing `Alt_L` means the ALT modifier is already held when the key event is
evaluated, so a bind with an empty modmask never matches — and it fails
silently, with no error. It's the same reason a Super launcher bind is
written `"SUPER + SUPER_L"`.

Get this wrong and Alt+Tab still opens the switcher (that's the separate
`"ALT + Tab"` bind), but releasing Alt never commits and the quick
tap-and-release does nothing.

The `mod` shortcut drives release-to-commit. hyprland-global-shortcuts-v1
defines both a `pressed` and a `released` event and Quickshell surfaces them
as separate signals, so one bind per key delivers both edges — no release
flag required.

While the panel is showing, `Escape`, `Enter` and `Delete` also work as plain
keys, so the `ALT + Escape` / `ALT + Delete` binds are optional — keep them if
you want those to work during the arm phase, before the panel appears.

To see what registered: `hyprctl globalshortcuts` — you should get
`hyprtab:mod`, `:next`, `:prev`, `:accept`, `:cancel`, `:closeAll`.

### Hyprland 0.54 and older (hyprlang)

```ini
bind = $mainMod, TAB, exec, qs ipc -c hyprtab call overview toggle
bind = , Alt_L, global, hyprtab:mod
bind = , Alt_R, global, hyprtab:mod
bind = ALT, Tab, global, hyprtab:next
bind = ALT SHIFT, Tab, global, hyprtab:prev
bind = ALT, Delete, global, hyprtab:closeAll
bind = ALT, escape, global, hyprtab:cancel
```

hyprtab detects which Hyprland it's talking to via Quickshell's
`Hyprland.usingLua` and emits the matching dispatcher syntax, so the same
config works on both. No edits needed when you upgrade.

### In-menu keys

| Key | Overview | Alt-Tab |
| --- | --- | --- |
| `Tab` / `Shift+Tab` | — | next / previous workspace |
| arrows, `hjkl` | move cursor (switches live) | — |
| `1`–`9`, `0` | jump to workspace | — |
| `Enter` | activate + close | — |
| `Esc` | close | cancel |
| `+` / `=` | new special workspace | — |
| `Delete` | — | close every window on the highlighted workspace |

Mouse: click a tile to switch, click a window to focus it, middle-click a
window to close it, drag a window onto another tile to move it, drag onto the
`+` tile to move it into a fresh special workspace.

---

## Theming with Noctalia v5

Noctalia v5 doesn't publish a stable `colors.json` for third parties any
more — plugins read colors through `noctalia.getColor(role)`, and external
apps (hyprtab is one) go through the **template** system.

**1.** Copy the template somewhere Noctalia can read it:

```sh
mkdir -p ~/.config/noctalia/templates
cp ~/.config/quickshell/hyprtab/noctalia-template/hyprtab-colors.json \
   ~/.config/noctalia/templates/hyprtab-colors.json
```

**2.** Register it in your Noctalia config:

```toml
[theme.templates.user.hyprtab]
input_path  = "$XDG_CONFIG_HOME/noctalia/templates/hyprtab-colors.json"
output_path = "$XDG_CONFIG_HOME/noctalia/hyprtab-colors.json"
```

**3.** Re-apply your theme once so Noctalia renders it.

That's it. `Config.qml` watches the rendered file, so changing your Noctalia
theme re-colors hyprtab live — no restart.

Token mapping (v5 Material 3 roles → hyprtab):

| Noctalia role | hyprtab |
| --- | --- |
| `surface` | panel + backdrop background |
| `on_surface` | text |
| `surface_variant` | workspace tile background |
| `on_surface_variant` | hover outline, divider |
| `surface_container_high` | window thumbnail fill |
| `primary` | selection ring + wash |
| `tertiary` | special-workspace accent |
| `outline` / `outline_variant` | panel border / window border |

Set `Config.useNoctaliaColors = false` to ignore all of it and use the hex
values in `Config.qml` directly. Every color has a hardcoded fallback, so a
missing or malformed file degrades gracefully instead of breaking.

Noctalia **v4** users: the old camelCase `colors.json` still works. Point
`Config.noctaliaColorsPath` at it; the lookup tries the v5 snake_case name
first and falls back to the v4 `mSurface`-style spelling.

---

## Hyprland blur

Set both backdrop opacities to `0` in `Config.qml` so the full-screen dim
layer doesn't sit on top of the blur:

```qml
property real altTabBackdropOpacity:   0.0
property real overviewBackdropOpacity: 0.0
```

Then let Hyprland blur the two layer namespaces (already in `hyprtab.lua`):

```lua
hl.layer_rule({ match = { namespace = "hyprtab" },          blur = true })
hl.layer_rule({ match = { namespace = "hyprtab-overview" }, blur = true })
```

Drop `altTabBackgroundOpacity` / `overviewBackgroundOpacity` to ~0.6 for a
more blur-forward look.

---

## Configuration

Everything lives in `Config.qml`. Highlights:

| Property | Default | Notes |
| --- | --- | --- |
| `overviewRows` / `overviewColumns` | `2` / `5` | workspace grid = rows × columns |
| `livePreviews` | `true` | live screencopy thumbnails |
| `showWindowIcons` | `true` | app icon badge on each thumbnail |
| `previewBackground` | `"solid"` | `"solid"` or `"wallpaper"` under previews |
| `wallpaperPath` | `""` | absolute path, no `~` |
| `tooltipEnabled` | `true` | title tooltip on window hover |
| `tooltipPosition` | `"above"` | `"above"` or `"below"` |
| `armDelayMs` | `180` | alt-tab anti-flash delay |
| `newSpecialPrefix` | `"stash"` | name for `+`-created special workspaces |

---

## Files

```
shell.qml              ShellRoot — instantiates AltTab + Overview
Config.qml             all tuning + Noctalia color integration  (singleton)
HyprData.qml           event-driven Hyprland model               (singleton)
WorkspaceTile.qml      one workspace: scaled live window previews
SelectionIndicator.qml floating selection ring
AltTab.qml             Alt+Tab MRU switcher
Overview.qml           Super+Tab overview (drag/drop, specials, tooltip)
qmldir                 module registration
hyprtab.lua            keybinds for Hyprland 0.55+
hyprtab.conf           keybinds for Hyprland 0.54 and older
noctalia-template/     Noctalia v5 color template
```

`HyprData` listens to Hyprland's socket2 event stream and mutates per-workspace
`ListModel`s in place — a window move destroys exactly one delegate and creates
exactly one, which is why drags don't flash. `hyprctl` is only consulted for
geometry that events don't carry.
