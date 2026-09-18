pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// All configuration for hyprtab. Both AltTab and Overview read from here.
// Edit values below; nothing else in the project should hardcode UI colors or
// magic numbers.
//
// COLOR SOURCING:
//   By default, colors are pulled from ~/.config/noctalia/colors.json on
//   startup (and hot-reloaded when that file changes). Each color property
//   below has a hardcoded fallback that's used if:
//     - useNoctaliaColors is false
//     - the file doesn't exist or fails to parse
//     - the specific Noctalia field is missing
//   To fully customize, set useNoctaliaColors to false and edit the hex
//   values directly.
QtObject {
    id: cfg

    //=========================================================================
    //  HYPRLAND COMPATIBILITY
    //=========================================================================
    // Which dispatcher syntax to send Hyprland.
    //   "auto"   - detect via Quickshell's Hyprland.usingLua, falling back to
    //              checking for ~/.config/hypr/hyprland.lua  (default)
    //   "always" - force Hyprland 0.55+ lua syntax
    //   "never"  - force legacy hyprlang syntax (0.54 and older)
    // Set this explicitly if detection guesses wrong; the symptom of guessing
    // wrong is a log line like:
    //   Dispatch request "focuswindow address:0x..." failed with error
    //   "error: [string "return hl.dispatch(focuswindow address:0x..."
    property string luaDispatch: "always"

    //=========================================================================
    //  NOCTALIA COLOR INTEGRATION
    //=========================================================================
    // Noctalia v5 no longer ships a stable colors.json for third parties —
    // plugins read colors through noctalia.getColor(role), and EXTERNAL apps
    // (which hyprtab is, being a Quickshell config) are served by the
    // TEMPLATE system instead. See README.md for the two-line Noctalia config
    // snippet that renders the file this reads.
    //
    // v5 tokens are snake_case Material 3 role names (surface, on_surface,
    // surface_variant, outline, primary, tertiary, ...). v4 used camelCase
    // with an "m" prefix (mSurface, mOnSurface, ...). We read v5 names first
    // and fall back to the v4 spelling, so this works on either version and
    // across the upgrade without edits.
    property bool useNoctaliaColors: true
    // Path to the rendered color file. The default is where the README's
    // template writes it. Watched for changes, so re-theming Noctalia
    // re-colors hyprtab live with no restart.
    property string noctaliaColorsPath:
        Quickshell.env("HOME") + "/.config/noctalia/hyprtab-colors.json"
    // Which variant to pull when the file happens to carry both (v4 shape).
    // The v5 template renders `default`, which already follows the active
    // theme mode, so this only matters for a v4-style file.
    property string noctaliaVariant: "dark"

    property var _noctaliaPalette: ({})

    property FileView _noctaliaFile: FileView {
        path: cfg.useNoctaliaColors && cfg.noctaliaColorsPath.length > 0
              ? cfg.noctaliaColorsPath : ""
        watchChanges: cfg.useNoctaliaColors
        // Not having the file is a normal state — it only exists once the
        // user registers the Noctalia template (see README). Every color has
        // a hardcoded fallback, so absence is silent, not an error.
        printErrors: false
        onFileChanged: reload()
        onLoaded: cfg._parseNoctaliaFile()
        onLoadFailed: cfg._noctaliaPalette = ({})
    }

    function _parseNoctaliaFile() {
        try {
            const raw = _noctaliaFile.text()
            if (!raw || raw.length === 0) {
                cfg._noctaliaPalette = ({}); return
            }
            const parsed = JSON.parse(raw)
            // Three shapes are accepted:
            //   v5 template output : flat { "surface": "#...", ... }
            //   v4 flat            : flat { "mSurface": "#...", ... }
            //   v4 per-mode        : { "dark": {...}, "light": {...} }
            let p = parsed
            if (parsed.surface === undefined && parsed.mSurface === undefined) {
                p = parsed[cfg.noctaliaVariant] || parsed
            }
            cfg._noctaliaPalette = p || ({})
        } catch (e) {
            console.warn("hyprtab: failed to parse Noctalia colors:", e)
            cfg._noctaliaPalette = ({})
        }
    }

    // Look up a color. `v5Key` is the snake_case Material role, `v4Key` the
    // legacy camelCase spelling; first hit wins, else `fallback`.
    function _nc(v5Key, v4Key, fallback) {
        if (!cfg.useNoctaliaColors) return fallback
        const a = cfg._noctaliaPalette[v5Key]
        if (typeof a === "string" && a.length > 0) return a
        const b = cfg._noctaliaPalette[v4Key]
        if (typeof b === "string" && b.length > 0) return b
        return fallback
    }

    //=========================================================================
    //  COLORS   (bind through _nc() so Noctalia can override the fallback)
    //=========================================================================
    property color backgroundColor:
        _nc("surface",                "mSurface",          "#010409")
    property color selectedBackground:
        _nc("primary",                "mPrimary",          "#58a6ff")
    property color textColor:
        _nc("on_surface",             "mOnSurface",        "#c9d1d9")
    property color selectedOutline:
        _nc("primary",                "mPrimary",          "#58a6ff")
    property color panelBorder:
        _nc("outline",                "mOutline",          "#30363d")
    property color tileBackground:
        _nc("surface_variant",        "mSurfaceVariant",   "#161b22")
    property color hoverOutline:
        _nc("on_surface_variant",     "mOnSurfaceVariant", "#8b949e")
    property color windowFill:
        _nc("surface_container_high", "mHover",            "#21262d")
    property color windowBorder:
        _nc("outline_variant",        "mOutline",          "#484f58")
    property color selectedTextColor:
        _nc("on_surface",             "mOnSurface",        "#c9d1d9")
    property color backdropColor:
        _nc("surface",                "mSurface",          "#010409")
    property color dividerColor:
        _nc("on_surface_variant",     "mOnSurfaceVariant", "#8b949e")
    property color specialAccent:
        _nc("tertiary",               "mTertiary",         "#bc8cff")

    //=========================================================================
    //  OPACITIES
    //=========================================================================
    property real backgroundOpacity:   0.85   // legacy default (unused; kept for back-compat)
    // Per-view panel background opacity.
    property real altTabBackgroundOpacity:   0.85
    property real overviewBackgroundOpacity: 0.85
    // Backdrop = full-screen dim layer behind the panel. Set to 0 to let
    // Hyprland's blur / whatever's underneath show through cleanly. Non-zero
    // adds a translucent dark wash over the whole screen while the menu is up.
    property real backdropOpacity:     0.0    // legacy default (unused; kept for back-compat)
    property real altTabBackdropOpacity:   0.0
    property real overviewBackdropOpacity: 0.0
    property real selectedTint:        0.15

    // Pre-computed panel backgrounds (color + opacity baked in). Bind to these
    // instead of recomputing Qt.rgba() in every consumer. They re-evaluate
    // when backgroundColor changes — which happens automatically when the
    // Noctalia palette file changes on disk.
    readonly property color altTabPanelBg:
        Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b,
                altTabBackgroundOpacity)
    readonly property color overviewPanelBg:
        Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b,
                overviewBackgroundOpacity)
    readonly property color tileBadgeBg:
        Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b, 0.78)
    readonly property color tooltipBg:
        Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b,
                tooltipBgOpacity)

    //=========================================================================
    //  GEOMETRY  (shared)
    //=========================================================================
    property real panelRadius:         20
    property real tileRadius:          12
    property real previewWidth:        250
    property real previewInset:        4
    property real tileSpacing:         8
    property real panelPadding:        12
    property real borderWidth:         1
    property real selectedBorderWidth: 2

    //=========================================================================
    //  ALT-TAB SPECIFIC
    //=========================================================================
    property int  altTabMaxColumns:    5      // wrap to a new row past this many tiles

    // Anti-flash: arm UI invisibly on first Tab; release before delay = silent dispatch
    property int  armDelayMs:          180
    property bool armSecondTapShows:   true

    //=========================================================================
    //  OVERVIEW SPECIFIC
    //=========================================================================
    property int  overviewColumns:     5      // workspaces per row (sequential)
    property int  overviewRows:        2      // number of normal rows (workspaces = rows * cols)
    property int  specialColumns:      5      // special workspace tiles per row
    property real overviewPreviewWidth: 250   // can match previewWidth; separate so you can tune
    property real dividerHeight:       1
    property real dividerSideFade:     90     // px of fade on each end of divider
    property real specialStripGap:     10     // gap above & below the divider

    //=========================================================================
    //  PREVIEWS
    //=========================================================================
    property bool livePreviews:        true    // live wayland screencopy
    property bool showWindowIcons:     true
    property real windowIconMax:       30
    property real windowIconOpacity:   0.85
    // Preview background: either "solid" (windowFill under the ScreencopyView,
    // opaque) or "wallpaper" (user's desktop wallpaper image under it, also
    // opaque). Either mode fixes the "transparent windows x-ray through the
    // overview" bug. Wallpaper mode looks nicer for transparent apps.
    property string previewBackground: "solid"    // "solid" | "wallpaper"
    // Path to the wallpaper image to use when previewBackground is "wallpaper".
    // Absolute path. Leave empty to fall back to solid.
    property string wallpaperPath:     ""

    //=========================================================================
    //  HOVER TOOLTIP  (window title popup on hover)
    //=========================================================================
    property bool   tooltipEnabled:        true
    property int    tooltipDelayMs:        10
    property real   tooltipMaxWidthFactor: 1.5
    property real   tooltipPadding:        8
    property real   tooltipBgOpacity:      0.95
    property real   tooltipGap:            4
    property string tooltipPosition:       "above"   // "above" | "below"

    //=========================================================================
    //  TYPOGRAPHY
    //=========================================================================
    property string fontFamily:        "GeistMono Nerd Font Mono"
    property real   labelPixelSize:    13

    //=========================================================================
    //  BEHAVIOR
    //=========================================================================
    property bool   skipUnmapped:             true
    property bool   includeSpecialWorkspaces: false  // alt-tab: include specials in cycle?
    property int    maxHistory:               12
    property string fallbackIcon:             "application-x-executable"

    // Default name prefix used when creating new special workspaces with the +
    // button.
    property string newSpecialPrefix:         "stash"
}
