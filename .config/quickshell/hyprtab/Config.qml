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
    //  NOCTALIA COLOR INTEGRATION
    //=========================================================================
    // Read colors from Noctalia's palette file. When true, the theme values
    // below are overridden by whatever Noctalia has set. Turn off to fully
    // control colors from this file.
    property bool useNoctaliaColors: true
    // Path to Noctalia's colors.json. Watched for changes on disk.
    property string noctaliaColorsPath: Quickshell.env("HOME") + "/.config/noctalia/colors.json"
    // "dark" or "light" — which variant of the palette to use. Noctalia's
    // JSON has both. Default to dark since this shell is dark-themed.
    property string noctaliaVariant: "dark"

    // Parsed Noctalia palette (an object with the mX fields). Empty {} until
    // the file loads (or if disabled / missing).
    property var _noctaliaPalette: ({})

    property FileView _noctaliaFile: FileView {
        path: cfg.useNoctaliaColors && cfg.noctaliaColorsPath.length > 0
              ? cfg.noctaliaColorsPath : ""
        watchChanges: cfg.useNoctaliaColors
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
            // Noctalia palettes have {"dark": {...}, "light": {...}} at the
            // top level. Colors are also sometimes stored flat (older schemes)
            // — support both shapes.
            let p = parsed[cfg.noctaliaVariant]
            if (!p && parsed.mSurface !== undefined) p = parsed
            cfg._noctaliaPalette = p || ({})
        } catch (e) {
            console.warn("hyprtab: failed to parse Noctalia colors:", e)
            cfg._noctaliaPalette = ({})
        }
    }

    // Small helper: return the Noctalia value for `key` if colors are enabled
    // and the palette has it, else return the given fallback.
    function _nc(key, fallback) {
        if (!cfg.useNoctaliaColors) return fallback
        const v = cfg._noctaliaPalette[key]
        return (typeof v === "string" && v.length > 0) ? v : fallback
    }

    //=========================================================================
    //  COLORS   (bind through _nc() so Noctalia can override the fallback)
    //=========================================================================
    property color backgroundColor:    _nc("mSurface",         "#010409")
    property color selectedBackground: _nc("mPrimary",         "#58a6ff")
    property color textColor:          _nc("mOnSurface",       "#c9d1d9")
    property color selectedOutline:    _nc("mPrimary",         "#58a6ff")
    property color panelBorder:        _nc("mOutline",         "#30363d")
    property color tileBackground:     _nc("mSurfaceVariant",  "#161b22")
    property color hoverOutline:       _nc("mOnSurfaceVariant","#8b949e")
    property color windowFill:         _nc("mHover",           "#21262d")
    property color windowBorder:       _nc("mOutline",         "#484f58")
    property color selectedTextColor:  _nc("mOnSurface",       "#c9d1d9")
    property color backdropColor:      _nc("mSurface",         "#010409")
    property color dividerColor:       _nc("mOnSurfaceVariant","#8b949e")
    property color specialAccent:      _nc("mTertiary",        "#bc8cff")

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
