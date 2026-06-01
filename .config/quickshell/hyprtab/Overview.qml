import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Super+Tab workspace overview. Sequential 1..N grid, then a fading divider,
// then a strip of currently-open special workspaces plus a "+" tile to spawn
// a new one. Click a workspace tile to switch; click a window to focus it;
// middle-click a window to close it.
Item {
    id: overview

    property bool active: false

    // --- CURSOR STATE ---
    // In the overview, navigating the cursor IS navigating workspaces — each
    // move also dispatches the switch live, so the cursor's position is always
    // the current workspace. One indicator, no dual highlight.
    property int selectedRow: 0   // 0 = normal grid, 1 = special strip
    property int selectedCol: 0   // flat index in the current row

    // --- model lists ---
    property var normalEntries: []
    property var specialEntries: []

    // tile registries — index -> tile Item — populated by delegates
    property var normalTiles: ({})
    property var specialTiles: ({})
    property Item plusTileItem: null

    function _rebuild() {
        // ----- normal workspaces: sequential 1..(rows*cols), populated or not -----
        const totalNormal = Config.overviewRows * Config.overviewColumns
        let normals = []
        for (let wid = 1; wid <= totalNormal; wid++) {
            const wins = HyprData.byWs[wid] || []
            const meta = HyprData.wsMeta[wid] || {}
            const monId = (meta.monId !== undefined) ? meta.monId : HyprData.focusedMonitorId
            const mon = HyprData.monitorById[monId] || { w: 16, h: 9 }
            normals.push({
                id: wid,
                name: String(wid),
                special: false,
                windows: wins,
                monW: mon.w || 16,
                monH: mon.h || 9
            })
        }
        overview.normalEntries = normals

        // ----- special workspaces: those currently open + ★create tile at end -----
        let specials = []
        for (const k in HyprData.wsMeta) {
            const idn = parseInt(k)
            const meta = HyprData.wsMeta[idn]
            if (!meta.special) continue
            const wins = HyprData.byWs[idn] || []
            const monId = (meta.monId !== undefined) ? meta.monId : HyprData.focusedMonitorId
            const mon = HyprData.monitorById[monId] || { w: 16, h: 9 }
            specials.push({
                id: idn,
                name: HyprData.specialName(meta.name) || meta.name,
                fullName: meta.name,
                special: true,
                windows: wins,
                monW: mon.w || 16,
                monH: mon.h || 9
            })
        }
        specials.sort((a, b) => a.name.localeCompare(b.name))
        overview.specialEntries = specials
    }

    Connections {
        target: HyprData
        function onUpdated() { overview._rebuild(); Qt.callLater(overview._refreshIndicators) }
    }

    // Note: we deliberately do NOT resync the cursor on `focusedWorkspaceChanged`
    // while the overview is open. Each of our own navigation keypresses triggers
    // a focused-workspace change, and an async resync would race with our local
    // model — producing exactly the "cursor stuck in middle row" feedback loop.
    // HyprData.dispatchSwitch updates monitorSpecial optimistically so internal
    // navigation stays consistent without needing a roundtrip refresh.
    //
    // External workspace changes are not expected while the overview holds
    // keyboard focus exclusively; if you do trigger one (via a script), reopen
    // the overview to re-snap.

    //=========================================================================
    //  IPC  (callable as `qs ipc -c hyprtab call overview <function>`)
    //=========================================================================
    IpcHandler {
        target: "overview"
        function toggle() { overview.active ? overview.close() : overview.open() }
        function open()   { overview.open() }
        function close()  { overview.close() }
    }

    // Super+Tab global shortcut to toggle (in addition to IPC).
    GlobalShortcut { appid: "hyprtab"; name: "overviewToggle"; onPressed: overview.active ? overview.close() : overview.open() }

    function open() {
        win.screen = root.focusedScreen() || win.screen
        HyprData.refresh()
        // Seed the cursor at the current workspace so the indicator opens
        // exactly where the user already is. Each subsequent move dispatches
        // a workspace switch live, so the cursor *is* the current workspace.
        overview._snapCursorToCurrent()
        overview.active = true
        Qt.callLater(overview._refreshIndicators)
    }

    function close() {
        overview.active = false
        normalIndicator.hide()
        specialIndicator.hide()
    }

    // Pick a cursor position that matches the focused workspace. Used only on
    // open() — during active navigation, the cursor is authoritative and
    // shouldn't be moved out from under the user.
    //
    // Special detection has two sources, in priority order, because both can be
    // stale right at startup:
    //   1. Hyprland.focusedWorkspace.name — if it starts with "special:" the
    //      user is on that special right now.
    //   2. HyprData.monitorSpecial[fmId] — what the last hyprctl monitors poll
    //      said was overlaid on the focused monitor.
    function _snapCursorToCurrent() {
        const rows = Config.overviewRows
        const cols = Config.overviewColumns
        const fw = Hyprland.focusedWorkspace
        const focusedName = (fw && typeof fw.name === "string") ? fw.name : ""
        const focusedIsSpecial = HyprData.isSpecial(fw ? fw.id : 1, focusedName)
        const specFromFocus = focusedIsSpecial ? HyprData.specialName(focusedName) : ""
        const specFromMon = HyprData.monitorSpecial[HyprData.focusedMonitorId] || ""
        const specName = specFromFocus.length > 0 ? specFromFocus : specFromMon

        if (specName.length > 0) {
            // place cursor in the special strip on that tile (or first special
            // if it's not yet present in our entries list)
            let si = -1
            for (let i = 0; i < overview.specialEntries.length; i++) {
                if (overview.specialEntries[i].name === specName) { si = i; break }
            }
            overview.selectedRow = 1
            overview.selectedCol = (si >= 0) ? si : 0
            return
        }
        // normal workspace: focusedWorkspace.id is the 1-based workspace number
        const curId = fw ? fw.id : 1
        const idx0 = curId - 1
        overview.selectedRow = 0
        overview.selectedCol = (idx0 >= 0 && idx0 < rows * cols) ? idx0 : 0
    }

    //=========================================================================
    //  KEYBOARD NAV  (each move dispatches the workspace switch live)
    //=========================================================================
    function _move(dx, dy) {
        const rows = Config.overviewRows
        const cols = Config.overviewColumns
        const specEntries = overview.specialEntries
        const specCount = specEntries.length + 1   // +1 for the "+" tile
        // wrap helper
        const wrap = (v, m) => ((v % m) + m) % m

        if (overview.selectedRow === 0) {
            // normal grid: cursor as flat index = row*cols + col
            const idx = overview.selectedCol
            let nrow = Math.floor(idx / cols)
            let ncol = idx % cols

            if (dx !== 0) {
                ncol = wrap(ncol + dx, cols)
            }
            if (dy !== 0) {
                nrow = nrow + dy
                if (nrow >= rows) {
                    // step DOWN out of normal grid -> special strip
                    overview.selectedRow = 1
                    overview.selectedCol = Math.min(ncol, specCount - 1)
                    overview._dispatchSelected()
                    return
                }
                if (nrow < 0) {
                    // step UP from top of normal grid -> wrap to special strip
                    overview.selectedRow = 1
                    overview.selectedCol = Math.min(ncol, specCount - 1)
                    overview._dispatchSelected()
                    return
                }
            }
            overview.selectedCol = nrow * cols + ncol
        } else {
            // special strip: 1D wrap horizontally
            let idx = overview.selectedCol
            if (dx !== 0) idx = wrap(idx + dx, specCount)
            if (dy !== 0) {
                // any vertical movement from the strip jumps back into normal
                // grid; going up enters last row at same column, going down
                // wraps to top row at same column
                const ncol = Math.min(idx, cols - 1)
                overview.selectedRow = 0
                overview.selectedCol = (dy < 0)
                                       ? ((rows - 1) * cols + ncol)
                                       : ncol
                overview._dispatchSelected()
                return
            }
            overview.selectedCol = idx
        }
        overview._dispatchSelected()
    }

    // Dispatch the workspace switch for the current cursor position.
    // No-op for the "+" tile (creation is on Enter or click only).
    function _dispatchSelected() {
        if (overview.selectedRow === 0) {
            const e = overview.normalEntries[overview.selectedCol]
            if (e) HyprData.dispatchSwitch(e.id, e.name)
        } else {
            const idx = overview.selectedCol
            if (idx === overview.specialEntries.length) return   // "+" tile: no live switch
            const e = overview.specialEntries[idx]
            if (e) HyprData.dispatchSwitch(e.id, e.fullName)
        }
    }

    function _activateSelection() {
        // For workspace tiles the cursor is already on that workspace, so
        // Enter just closes the overview. For the "+" tile, create a new
        // special workspace.
        if (overview.selectedRow === 1
            && overview.selectedCol === overview.specialEntries.length) {
            HyprData.createNewSpecial()
        }
        overview.close()
    }

    // Drive the two floating indicators based on cursor state.
    function _refreshIndicators() {
        if (!overview.active) {
            normalIndicator.hide()
            specialIndicator.hide()
            return
        }
        if (overview.selectedRow === 0) {
            specialIndicator.hide()
            const t = overview.normalTiles[overview.selectedCol]
            if (t) normalIndicator.moveTo(t, false)
            else   normalIndicator.hide()
        } else {
            normalIndicator.hide()
            const idx = overview.selectedCol
            const t = (idx === overview.specialEntries.length)
                      ? overview.plusTileItem
                      : overview.specialTiles[idx]
            if (t) specialIndicator.moveTo(t, true)
            else   specialIndicator.hide()
        }
    }

    onSelectedRowChanged: overview._refreshIndicators()
    onSelectedColChanged: overview._refreshIndicators()
    onActiveChanged:      overview._refreshIndicators()

    //=========================================================================
    //  UI
    //=========================================================================
    PanelWindow {
        id: win
        visible: overview.active
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hyprtab-overview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // backdrop + click-outside-to-close
        Rectangle {
            anchors.fill: parent
            color: Config.backdropColor
            opacity: Config.backdropOpacity
            MouseArea { anchors.fill: parent; onClicked: overview.close() }
        }

        // capture keys at the panel-window level
        Item {
            anchors.fill: parent
            focus: overview.active
            Keys.onEscapePressed: overview.close()
            Keys.onReturnPressed: overview._activateSelection()
            Keys.onLeftPressed:   overview._move(-1,  0)
            Keys.onRightPressed:  overview._move( 1,  0)
            Keys.onUpPressed:     overview._move( 0, -1)
            Keys.onDownPressed:   overview._move( 0,  1)
            Keys.onPressed: function(event) {
                // vim-style hjkl
                if      (event.key === Qt.Key_H) { overview._move(-1, 0); event.accepted = true }
                else if (event.key === Qt.Key_L) { overview._move( 1, 0); event.accepted = true }
                else if (event.key === Qt.Key_K) { overview._move( 0,-1); event.accepted = true }
                else if (event.key === Qt.Key_J) { overview._move( 0, 1); event.accepted = true }
                else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                    HyprData.createNewSpecial(); overview.close(); event.accepted = true
                }
                // number row 1-9 jumps the cursor (and dispatches) without closing
                else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    const n = event.key - Qt.Key_0
                    if (n - 1 < overview.normalEntries.length) {
                        overview.selectedRow = 0
                        overview.selectedCol = n - 1
                        overview._dispatchSelected()
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_0) {
                    if (9 < overview.normalEntries.length) {
                        overview.selectedRow = 0
                        overview.selectedCol = 9
                        overview._dispatchSelected()
                    }
                    event.accepted = true
                }
            }
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            radius: Config.panelRadius
            color: Qt.rgba(Config.backgroundColor.r,
                           Config.backgroundColor.g,
                           Config.backgroundColor.b,
                           Config.backgroundOpacity)
            border.width: Config.borderWidth
            border.color: Config.panelBorder
            implicitWidth:  contentCol.implicitWidth  + Config.panelPadding * 2
            implicitHeight: contentCol.implicitHeight + Config.panelPadding * 2

            Column {
                id: contentCol
                anchors.centerIn: parent
                spacing: Config.specialStripGap

                // ----- normal workspace grid -----
                // Wrapped in an Item so the SelectionIndicator overlay can be
                // a sibling of the Grid (not a child — that would make Grid lay
                // the indicator out as a phantom cell past the last tile).
                Item {
                    id: normalGridWrap
                    implicitWidth:  normalGrid.implicitWidth
                    implicitHeight: normalGrid.implicitHeight

                    Grid {
                        id: normalGrid
                        anchors.centerIn: parent
                        columns: Config.overviewColumns
                        spacing: Config.tileSpacing

                        Repeater {
                            model: overview.normalEntries
                            delegate: WorkspaceTile {
                                required property var modelData
                                required property int index
                                wsId: modelData.id
                                wsName: modelData.name
                                special: false
                                windows: modelData.windows
                                monW: modelData.monW
                                monH: modelData.monH
                                Component.onCompleted: {
                                    let m = overview.normalTiles
                                    m[index] = this
                                    overview.normalTiles = m
                                    if (overview.active
                                        && overview.selectedRow === 0
                                        && overview.selectedCol === index)
                                        Qt.callLater(overview._refreshIndicators)
                                }
                                Component.onDestruction: {
                                    let m = overview.normalTiles
                                    if (m[index] === this) { delete m[index]; overview.normalTiles = m }
                                }
                                onTileClicked: {
                                    overview.selectedRow = 0
                                    overview.selectedCol = index
                                    overview._dispatchSelected()
                                    overview.close()
                                }
                                onWindowClicked: function(addr) {
                                    Hyprland.dispatch("focuswindow address:" + addr)
                                    overview.close()
                                }
                                onWindowMiddleClicked: function(addr) {
                                    Hyprland.dispatch("closewindow address:" + addr)
                                    HyprData.refresh()
                                }
                            }
                        }
                    }

                    // overlay anchored to the grid bounds, sharing its coord space
                    Item {
                        anchors.fill: normalGrid
                        z: 5
                        SelectionIndicator { id: normalIndicator }
                    }
                }

                // ----- divider: thin line with symmetric end-fades -----
                // Implemented as three rectangles (left fade, solid mid, right fade)
                // so we avoid pulling in QtQuick.Shapes which isn't guaranteed
                // to be available in every Quickshell install.
                Item {
                    id: divider
                    width: normalGrid.width
                    height: Config.dividerHeight

                    Row {
                        anchors.fill: parent
                        spacing: 0
                        Rectangle {
                            width: Math.min(Config.dividerSideFade, divider.width / 2)
                            height: parent.height
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Config.dividerColor }
                            }
                        }
                        Rectangle {
                            width: Math.max(0, divider.width
                                              - 2 * Math.min(Config.dividerSideFade, divider.width / 2))
                            height: parent.height
                            color: Config.dividerColor
                        }
                        Rectangle {
                            width: Math.min(Config.dividerSideFade, divider.width / 2)
                            height: parent.height
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Config.dividerColor }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                    }
                }

                // ----- special workspace strip + create tile -----
                // Same wrapper pattern as the normal grid above.
                Item {
                    id: specialGridWrap
                    implicitWidth:  specialGrid.implicitWidth
                    implicitHeight: specialGrid.implicitHeight

                    Grid {
                        id: specialGrid
                        anchors.centerIn: parent
                        columns: Math.max(1, Math.min(
                                              overview.specialEntries.length + 1,
                                              Config.specialColumns))
                        spacing: Config.tileSpacing

                        Repeater {
                            model: overview.specialEntries
                            delegate: WorkspaceTile {
                                required property var modelData
                                required property int index
                                wsId: modelData.id
                                wsName: modelData.name
                                special: true
                                windows: modelData.windows
                                monW: modelData.monW
                                monH: modelData.monH
                                Component.onCompleted: {
                                    let m = overview.specialTiles
                                    m[index] = this
                                    overview.specialTiles = m
                                    if (overview.active
                                        && overview.selectedRow === 1
                                        && overview.selectedCol === index)
                                        Qt.callLater(overview._refreshIndicators)
                                }
                                Component.onDestruction: {
                                    let m = overview.specialTiles
                                    if (m[index] === this) { delete m[index]; overview.specialTiles = m }
                                }
                                onTileClicked: {
                                    overview.selectedRow = 1
                                    overview.selectedCol = index
                                    overview._dispatchSelected()
                                    overview.close()
                                }
                                onWindowClicked: function(addr) {
                                    Hyprland.dispatch("focuswindow address:" + addr)
                                    overview.close()
                                }
                                onWindowMiddleClicked: function(addr) {
                                    Hyprland.dispatch("closewindow address:" + addr)
                                    HyprData.refresh()
                                }
                            }
                        }

                        // "+" tile — visually a regular empty workspace tile whose
                        // label is just "+" (no oversized glyph, no subtitle), to
                        // match the "Empty" wording used on real empty workspaces.
                        Item {
                            id: plusTile

                            readonly property real innerW: Config.previewWidth - Config.previewInset * 2
                            readonly property real innerH:
                                Math.max(60, innerW * (9 / 16))
                            implicitWidth: Config.previewWidth
                            implicitHeight: innerH + Config.previewInset * 2

                            Component.onCompleted: {
                                overview.plusTileItem = this
                                if (overview.active
                                    && overview.selectedRow === 1
                                    && overview.selectedCol === overview.specialEntries.length)
                                    Qt.callLater(overview._refreshIndicators)
                            }

                            Rectangle {
                                id: plusBg
                                anchors.fill: parent
                                radius: Config.tileRadius
                                color: Config.tileBackground
                                border.width: Config.borderWidth
                                border.color: plusHover.hovered ? Config.hoverOutline : Config.panelBorder
                                Behavior on border.color { ColorAnimation { duration: 90 } }

                                // label rendered identically to the "Empty" hint
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: Config.textColor
                                    opacity: 0.4
                                    font.pixelSize: Config.labelPixelSize
                                    font.family: Config.fontFamily.length > 0
                                                 ? Config.fontFamily : Qt.application.font.family
                                }

                                MouseArea {
                                    id: plusHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { HyprData.createNewSpecial(); overview.close() }
                                }
                            }
                        }
                    }

                    // overlay anchored to the special grid, sharing its coord space
                    Item {
                        anchors.fill: specialGrid
                        z: 5
                        SelectionIndicator { id: specialIndicator }
                    }
                }
            }
        }
    }
}
