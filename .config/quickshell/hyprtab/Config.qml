pragma Singleton
import QtQuick

// All configuration for hyprtab. Both AltTab and Overview read from here.
// Edit values; nothing else in the project should hardcode UI numbers/colors.
QtObject {
    id: cfg

    //=========================================================================
    //  COLORS  (Noctalia dark theme defaults)
    //=========================================================================
    property color backgroundColor:    "#010409"   // mSurface
    property color selectedBackground: "#58a6ff"   // mPrimary — selection wash
    property color textColor:          "#c9d1d9"   // mOnSurface
    property color selectedOutline:    "#58a6ff"   // mPrimary — selection ring
    property color panelBorder:        "#30363d"   // mOutline
    property color tileBackground:     "#161b22"   // mSurfaceVariant — mini-desktop "screen"
    property color hoverOutline:       "#8b949e"   // mOnSurfaceVariant — tile hover border
    property color windowFill:         "#21262d"   // mHover — window box fill
    property color windowBorder:       "#484f58"   // window box outline
    property color selectedTextColor:  "#c9d1d9"   // mOnSurface — label of selected tile
    property color backdropColor:      "#010409"   // dim behind the panel
    property color dividerColor:       "#8b949e"   // mOnSurfaceVariant — overview divider line
    property color specialAccent:      "#bc8cff"   // mTertiary — special workspace accent

    //=========================================================================
    //  OPACITIES
    //=========================================================================
    property real backgroundOpacity:   0.85   // legacy default (unused; kept for back-compat)
    // Per-view panel background opacity.
    property real altTabBackgroundOpacity:   0.85
    property real overviewBackgroundOpacity: 0.85
    property real backdropOpacity:     0.15   // legacy default (unused; kept for back-compat)
    // Per-view backdrop (full-screen dim layer) opacity.
    property real altTabBackdropOpacity:   0.15
    property real overviewBackdropOpacity: 0.15
    property real selectedTint:        0.15

    // Pre-computed panel backgrounds (color + opacity baked in). Bind to these
    // instead of recomputing Qt.rgba() in every consumer — saves a function
    // call per re-evaluation. These re-evaluate only when their dependencies
    // change, which is essentially never at runtime.
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
    property int  overviewRows:        2      // number of normal rows shown (workspaces = rows*cols)
    property int  specialColumns:      5      // special workspace tiles per row
    property real overviewPreviewWidth: 250   // can match previewWidth; separate so you can tune
    property real dividerHeight:       1
    property real dividerSideFade:     90     // pixels of fade on each end of divider
    property real specialStripGap:     10     // gap above & below the divider

    //=========================================================================
    //  PREVIEWS
    //=========================================================================
    property bool livePreviews:        true   // live wayland screencopy of each window
    property bool showWindowIcons:     true
    property real windowIconMax:       30
    property real windowIconOpacity:   0.85

    //=========================================================================
    //  HOVER TOOLTIP  (window title popup on hover)
    //=========================================================================
    // Whether to show a tooltip with the window title when hovering a window.
    property bool   tooltipEnabled:        true
    // Delay before the tooltip appears, in ms. 0 = instant.
    property int    tooltipDelayMs:        10
    // Tooltip max width as a multiple of the tile width. Text wraps past this.
    property real   tooltipMaxWidthFactor: 1.5
    // Tooltip padding inside the box (px).
    property real   tooltipPadding:        8
    // Tooltip background opacity (the body is Config.backgroundColor at this
    // alpha). The border is panelBorder.
    property real   tooltipBgOpacity:      0.95
    // Vertical gap between the hovered window and the tooltip (px).
    property real   tooltipGap:            4
    // Where to position the tooltip relative to the hovered window.
    // "above" or "below". May overflow the panel — that's allowed.
    property string tooltipPosition:       "above"

    //=========================================================================
    //  TYPOGRAPHY
    //=========================================================================
    property string fontFamily:        "GeistMono Nerd Font Mono"
    property real   labelPixelSize:    13

    //=========================================================================
    //  BEHAVIOR
    //=========================================================================
    property bool   skipUnmapped:             true
    property bool   includeSpecialWorkspaces: false  // alt-tab only: include specials in cycle?
    property int    maxHistory:               12
    property string fallbackIcon:             "application-x-executable"

    // Default name prefix used when creating new special workspaces with the +
    // button (matches Shanu-Kumawat/quickshell-overview behavior).
    property string newSpecialPrefix:         "stash"
}
