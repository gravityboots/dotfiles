import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Super+Tab workspace overview, event-driven edition.
//
// Architecture:
//   The model lives in HyprData. Hyprland's socket2 stream drives all window
//   mutations directly into per-workspace ListModels. This UI is purely a
//   reactive view: it never mutates state, never reconciles, never polls. A
//   drag dispatches movetoworkspacesilent and clears local drag UI; the
//   movewindow event coming back from Hyprland updates the model. Same for
//   close: middle-click dispatches closewindow and the closewindow event
//   removes the row. All transitions are smooth because per-ws ListModels
//   are address-stable — moving a window destroys exactly one delegate in
//   the source tile and creates exactly one in the destination.
//
// What this file owns:
//   - cursor position (selectedRow/Col) and indicator placement
//   - keyboard navigation (each move dispatches workspace switch live)
//   - workspace entry lists (normalEntries / specialEntries) — REBUILT only
//     when HyprData.workspacesChanged() fires, i.e. when a workspace appears
//     or disappears. Window changes never touch these arrays.
//   - drag UI: the floating ghost, drop-target hit-test, dispatch on release.
//     No model mutation here; the event socket drives the model.
Item {
    id: overview

    property bool active: false

    // cursor — row 0 = normal grid, row 1 = special strip
    property int selectedRow: 0
    property int selectedCol: 0

    // workspace-level entry lists (id/name/monitor) — DO NOT contain windows.
    // Each tile binds its inner Repeater to HyprData.windowsFor(modelData.id)
    // directly, so window churn never touches these arrays.
    property var normalEntries: []
    property var specialEntries: []

    // tile registries — index -> tile Item — populated by delegates
    property var normalTiles: ({})
    property var specialTiles: ({})
    property Item plusTileItem: null

    // --- DRAG STATE ---
    // The drag is purely visual. We never pluck the window out of any model.
    // On release we dispatch movetoworkspacesilent; the event-driven model
    // observes Hyprland's movewindow event and removes-from-source + appends-
    // to-destination via direct ListModel ops. That's what makes the move
    // smooth and flash-free: one delegate down, one delegate up, no churn
    // elsewhere.
    property bool dragActive: false
    property string dragAddress: ""
    property string dragIcon: ""
    property string dragTitle: ""
    property var    dragWl: null
    property real   dragW: 220
    property real   dragH: 44
    property real   dragGrabDX: 0
    property real   dragGrabDY: 0
    property real   dragX: 0
    property real   dragY: 0
    property string dropTargetKey: ""
    property int    _dragSrcWs: -1

    // --- TOOLTIP STATE ---
    // The tooltip floats above all tiles, showing the hovered window's title.
    // _ttPendingTitle is set on hover-enter; _ttTimer fires after the
    // configured delay and promotes it to _ttTitle (which makes the tooltip
    // visible). Hover-exit clears both immediately. Drag start clears too.
    property string _ttTitle: ""              // currently shown title ("" = hidden)
    property string _ttPendingTitle: ""       // waiting to become _ttTitle
    property real   _ttAnchorX: 0             // window top-left in global coords
    property real   _ttAnchorY: 0
    property real   _ttAnchorW: 0             // hovered window box width
    property real   _ttAnchorH: 0             //   and height

    //=========================================================================
    //  WORKSPACE-LEVEL REBUILD
    //=========================================================================
    // Called when HyprData reports a workspace appeared/disappeared (or on
    // startup). The window lists are NOT in normalEntries — each tile binds
    // its windowsModel to HyprData.windowsFor(id) directly. We only need to
    // refresh this when the set of workspaces themselves changes.
    function _rebuildWorkspaces() {
        // Normal: sequential 1..(rows*cols), populated or not.
        const totalNormal = Config.overviewRows * Config.overviewColumns
        let normals = []
        for (let wid = 1; wid <= totalNormal; wid++) {
            const meta = HyprData.workspaces[wid] || {}
            const monId = (meta.monId !== undefined) ? meta.monId : HyprData.focusedMonitorId
            const mon = HyprData.monitorById[monId] || { w: 16, h: 9 }
            normals.push({
                id: wid,
                name: String(wid),
                monW: mon.w || 16,
                monH: mon.h || 9
            })
        }
        overview.normalEntries = normals

        // Special: every currently-open special workspace.
        let specials = []
        for (const k in HyprData.workspaces) {
            const idn = parseInt(k)
            const meta = HyprData.workspaces[idn]
            if (!meta.special) continue
            const monId = (meta.monId !== undefined) ? meta.monId : HyprData.focusedMonitorId
            const mon = HyprData.monitorById[monId] || { w: 16, h: 9 }
            specials.push({
                id: idn,
                name: HyprData.specialName(meta.name) || meta.name,
                fullName: meta.name,
                monW: mon.w || 16,
                monH: mon.h || 9
            })
        }
        specials.sort((a, b) => a.name.localeCompare(b.name))
        overview.specialEntries = specials
    }

    // Rebuild only on STRUCTURAL workspace change (add/remove/rename). Also
    // on geometry-sync completion (first bootstrap, post-event re-sync) so we
    // don't miss the initial state. The rebuild is cheap and idempotent.
    Connections {
        target: HyprData
        function onWorkspacesChanged() {
            overview._rebuildWorkspaces()
            Qt.callLater(overview._refreshIndicators)
        }
        function onUpdated() {
            if (overview.active) {
                overview._rebuildWorkspaces()
                Qt.callLater(overview._refreshIndicators)
            }
        }
    }

    Component.onCompleted: overview._rebuildWorkspaces()

    //=========================================================================
    //  IPC + SHORTCUTS
    //=========================================================================
    IpcHandler {
        target: "overview"
        function toggle() { overview.active ? overview.close() : overview.open() }
        function open()   { overview.open() }
        function close()  { overview.close() }
    }

    GlobalShortcut { appid: "hyprtab"; name: "overviewToggle"
                     onPressed: overview.active ? overview.close() : overview.open() }

    function open() {
        win.screen = root.focusedScreen() || win.screen
        // safety: clear any stale drag state
        overview.dragActive = false
        overview.dragAddress = ""
        overview.dropTargetKey = ""
        overview._internallySwitching = false  // start fresh
        // Force Hyprland to refresh its workspace view in case we missed
        // events while the overview was hidden — needed so focusedWorkspace
        // reflects reality (e.g. user pressed SUPER+1 outside the overview).
        try { if (Hyprland.refreshWorkspaces) Hyprland.refreshWorkspaces() } catch (e) {}
        try { if (Hyprland.refreshMonitors)   Hyprland.refreshMonitors()   } catch (e) {}
        overview._rebuildWorkspaces()
        overview._snapCursorToCurrent()
        overview.active = true
        Qt.callLater(overview._refreshIndicators)
        // Re-snap on the next tick: refreshWorkspaces is async-ish and
        // focusedWorkspace may settle to its true value a frame later.
        Qt.callLater(function() {
            overview._snapCursorToCurrent()
            overview._refreshIndicators()
        })
        // also kick a sync so geometry data is fresh
        HyprData.refresh()
    }

    function close() {
        overview.active = false
        overview.dragActive = false
        overview.dragAddress = ""
        overview.dropTargetKey = ""
        overview._hideTooltip()
        normalIndicator.hide()
        specialIndicator.hide()
    }

    //=========================================================================
    //  CURSOR + NAVIGATION
    //=========================================================================
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
            let si = -1
            for (let i = 0; i < overview.specialEntries.length; i++) {
                if (overview.specialEntries[i].name === specName) { si = i; break }
            }
            overview.selectedRow = 1
            overview.selectedCol = (si >= 0) ? si : 0
            return
        }
        const curId = fw ? fw.id : 1
        const idx0 = curId - 1
        overview.selectedRow = 0
        overview.selectedCol = (idx0 >= 0 && idx0 < rows * cols) ? idx0 : 0
    }

    function _move(dx, dy) {
        const rows = Config.overviewRows
        const cols = Config.overviewColumns
        const specCount = overview.specialEntries.length + 1   // +1 for the "+" tile
        const wrap = (v, m) => ((v % m) + m) % m

        if (overview.selectedRow === 0) {
            const idx = overview.selectedCol
            let nrow = Math.floor(idx / cols)
            let ncol = idx % cols
            if (dx !== 0) ncol = wrap(ncol + dx, cols)
            if (dy !== 0) {
                nrow = nrow + dy
                if (nrow >= rows || nrow < 0) {
                    overview.selectedRow = 1
                    overview.selectedCol = Math.min(ncol, specCount - 1)
                    overview._dispatchSelected()
                    return
                }
            }
            overview.selectedCol = nrow * cols + ncol
        } else {
            let idx = overview.selectedCol
            if (dx !== 0) idx = wrap(idx + dx, specCount)
            if (dy !== 0) {
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

    // True while the user's own navigation key triggered a dispatch we're
    // waiting to see come back as focusedWorkspaceChanged. Used to distinguish
    // "I caused this switch" from "something external switched the workspace"
    // (e.g. user pressed SUPER+1 while the overview is open). Cleared on the
    // very next focusedWorkspaceChanged that matches our cursor.
    property bool _internallySwitching: false

    function _dispatchSelected() {
        if (overview.selectedRow === 0) {
            const e = overview.normalEntries[overview.selectedCol]
            if (e) {
                overview._internallySwitching = true
                HyprData.dispatchSwitch(e.id, e.name)
            }
        } else {
            const idx = overview.selectedCol
            if (idx === overview.specialEntries.length) return   // "+" tile
            const e = overview.specialEntries[idx]
            if (e) {
                overview._internallySwitching = true
                HyprData.dispatchSwitch(e.id, e.fullName)
            }
        }
    }

    // External workspace switch (e.g. user pressed SUPER+1 with overview open):
    // snap our cursor to match. The internal flag is to ignore the echo of our
    // own dispatches.
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (!overview.active) return
            if (overview._internallySwitching) {
                // This change is the echo of our own dispatch — consume the
                // flag and don't snap (cursor is already correct).
                overview._internallySwitching = false
                return
            }
            overview._snapCursorToCurrent()
        }
    }

    function _activateSelection() {
        if (overview.selectedRow === 1
            && overview.selectedCol === overview.specialEntries.length) {
            HyprData.createNewSpecial()
        }
        overview.close()
    }

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
            const onPlus = (idx === overview.specialEntries.length)
            const t = onPlus ? overview.plusTileItem : overview.specialTiles[idx]
            if (t) specialIndicator.moveTo(t, true)
            else   specialIndicator.hide()
        }
    }

    onSelectedRowChanged: overview._refreshIndicators()
    onSelectedColChanged: overview._refreshIndicators()
    onActiveChanged:      overview._refreshIndicators()

    //=========================================================================
    //  WINDOW ACTIONS  (dispatch-only — no model mutation)
    //=========================================================================
    // Close a window: just dispatch. The closewindow event in HyprData will
    // splice the row out of the workspace's ListModel and the matching
    // delegate will be destroyed. No timer, no reconcile, no race.
    function _closeWindow(wsId, addr) {
        Hyprland.dispatch("closewindow address:" + addr)
    }

    //=========================================================================
    //  DRAG  (visual only — Hyprland events drive the model)
    //=========================================================================
    function _onWindowDragStarted(srcWsId, payload) {
        overview.dragAddress = payload.address
        overview.dragIcon = payload.icon
        overview.dragTitle = payload.title
        overview.dragWl = payload.wl
        overview.dragW = payload.w
        overview.dragH = payload.h
        overview.dragGrabDX = payload.grabDX
        overview.dragGrabDY = payload.grabDY
        overview.dropTargetKey = ""
        overview._dragSrcWs = srcWsId
        overview.dragActive = true
        overview._hideTooltip()
    }
    function _onWindowDragMoved(gx, gy) {
        if (!overview.dragActive) return
        const p = panel.mapFromGlobal(gx, gy)
        overview.dragX = p.x - overview.dragGrabDX
        overview.dragY = p.y - overview.dragGrabDY
        overview.dropTargetKey = overview._hitTestTile(gx, gy)
    }
    function _onWindowDragEnded(gx, gy) {
        if (!overview.dragActive) return
        const key = overview._hitTestTile(gx, gy)
        const addr = overview.dragAddress
        overview.dragActive = false
        overview.dropTargetKey = ""
        if (!key) {
            // dropped outside any tile — clearing dragAddress un-hides source
            overview.dragAddress = ""
            return
        }
        // dispatch the move; the movewindow event will update the model.
        // clear dragAddress so the source frame stays hidden ONLY while the
        // event-driven move arrives (typically <16ms). If the dispatch fails
        // outright, the frame returns immediately — which is correct.
        overview.dragAddress = ""
        overview._performDrop(key, addr)
    }

    function _hitTestTile(gx, gy) {
        function hit(item) {
            if (!item) return false
            const p = item.mapFromGlobal(gx, gy)
            return p.x >= 0 && p.y >= 0 && p.x < item.width && p.y < item.height
        }
        for (const k in overview.normalTiles)
            if (hit(overview.normalTiles[k])) return "n:" + k
        for (const k in overview.specialTiles)
            if (hit(overview.specialTiles[k])) return "s:" + k
        if (hit(overview.plusTileItem)) return "plus"
        return ""
    }

    function _performDrop(key, addr) {
        if (key === "plus") {
            // Find a fresh special name, dispatch the move. Hyprland's
            // createworkspace event will append the new ws to HyprData
            // (which fires workspacesChanged → _rebuildWorkspaces), and
            // movewindow will add the row to its ListModel.
            const taken = {}
            for (const e of overview.specialEntries) taken[e.name] = true
            let base = Config.newSpecialPrefix
            let candidate = base
            let i = 2
            while (taken[candidate]) candidate = base + "-" + (i++)
            Hyprland.dispatch("movetoworkspacesilent special:" + candidate + ",address:" + addr)
            return
        }
        const parts = key.split(":")
        if (parts[0] === "n") {
            const idx = parseInt(parts[1])
            const e = overview.normalEntries[idx]
            if (!e) return
            Hyprland.dispatch("movetoworkspacesilent " + e.id + ",address:" + addr)
        } else if (parts[0] === "s") {
            const idx = parseInt(parts[1])
            const e = overview.specialEntries[idx]
            if (!e) return
            Hyprland.dispatch("movetoworkspacesilent " + e.fullName + ",address:" + addr)
        }
    }

    //=========================================================================
    //  HOVER TOOLTIP
    //=========================================================================
    // The tooltip is a single floating Item inside the panel. Hover events
    // from any WorkspaceTile drive its title + anchor position. A delay timer
    // suppresses flash-on-pass: the tooltip only appears if the cursor stays
    // on the same window for `tooltipDelayMs` ms.
    //
    // Once shown, subsequent hover-enters on OTHER windows refresh the title
    // immediately (no second delay) — once the user is in tooltip-browsing
    // mode, the tooltip moves with them.
    function _onWindowHoverEntered(title, gx, gy, w, h) {
        if (!Config.tooltipEnabled) return
        if (overview.dragActive) return
        overview._ttAnchorX = gx
        overview._ttAnchorY = gy
        overview._ttAnchorW = w
        overview._ttAnchorH = h
        if (overview._ttTitle.length > 0) {
            // already in tooltip-browsing mode — refresh immediately
            overview._ttTitle = title
            _ttTimer.stop()
        } else {
            // not yet showing — arm the delay
            overview._ttPendingTitle = title
            _ttTimer.restart()
        }
    }
    function _onWindowHoverExited(title) {
        // Only hide if the exit is for the title currently pending/showing.
        // (Avoids a rapid enter-A → enter-B → exit-A sequence killing the
        // tooltip we just refreshed to B's title.)
        if (overview._ttPendingTitle === title) {
            overview._ttPendingTitle = ""
            _ttTimer.stop()
        }
        if (overview._ttTitle === title) {
            overview._ttTitle = ""
        }
    }
    function _hideTooltip() {
        overview._ttTitle = ""
        overview._ttPendingTitle = ""
        _ttTimer.stop()
    }

    Timer {
        id: _ttTimer
        interval: Math.max(0, Config.tooltipDelayMs)
        repeat: false
        onTriggered: {
            if (overview._ttPendingTitle.length > 0) {
                overview._ttTitle = overview._ttPendingTitle
            }
        }
    }

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
            opacity: Config.overviewBackdropOpacity
            MouseArea { anchors.fill: parent; onClicked: overview.close() }
        }

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
                if      (event.key === Qt.Key_H) { overview._move(-1, 0); event.accepted = true }
                else if (event.key === Qt.Key_L) { overview._move( 1, 0); event.accepted = true }
                else if (event.key === Qt.Key_K) { overview._move( 0,-1); event.accepted = true }
                else if (event.key === Qt.Key_J) { overview._move( 0, 1); event.accepted = true }
                else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                    HyprData.createNewSpecial(); overview.close(); event.accepted = true
                }
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
            color: Config.overviewPanelBg
            border.width: Config.borderWidth
            border.color: Config.panelBorder
            implicitWidth:  contentCol.implicitWidth  + Config.panelPadding * 2
            implicitHeight: contentCol.implicitHeight + Config.panelPadding * 2

            Column {
                id: contentCol
                anchors.centerIn: parent
                spacing: Config.specialStripGap

                // ----- normal workspace grid -----
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
                                // Bind windows directly from the singleton's
                                // event-driven ListModel for this workspace.
                                // The reference is stable across the lifetime
                                // of the tile, so the inner Repeater is also
                                // stable; only append/remove/set on the
                                // ListModel itself drives delegate creation.
                                windowsModel: HyprData.windowsFor(modelData.id)
                                monW: modelData.monW
                                monH: modelData.monH
                                // Only stream wayland captures while the
                                // overview is visible — saves the bulk of
                                // memory & GPU when closed.
                                previewsActive: overview.active
                                dropHighlight: overview.dragActive
                                               && overview.dropTargetKey === ("n:" + index)
                                draggingAddress: overview.dragActive ? overview.dragAddress : ""
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
                                    overview._closeWindow(modelData.id, addr)
                                }
                                onWindowDragStarted: function(payload) {
                                    overview._onWindowDragStarted(modelData.id, payload)
                                }
                                onWindowDragMoved: function(gx, gy) {
                                    overview._onWindowDragMoved(gx, gy)
                                }
                                onWindowDragEnded: function(gx, gy) {
                                    overview._onWindowDragEnded(gx, gy)
                                }
                                onWindowHoverEntered: function(title, gx, gy, w, h) {
                                    overview._onWindowHoverEntered(title, gx, gy, w, h)
                                }
                                onWindowHoverExited: function(title) {
                                    overview._onWindowHoverExited(title)
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: normalGrid
                        z: 5
                        SelectionIndicator { id: normalIndicator }
                    }
                }

                // ----- divider -----
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
                                windowsModel: HyprData.windowsFor(modelData.id)
                                monW: modelData.monW
                                monH: modelData.monH
                                previewsActive: overview.active
                                dropHighlight: overview.dragActive
                                               && overview.dropTargetKey === ("s:" + index)
                                draggingAddress: overview.dragActive ? overview.dragAddress : ""
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
                                    overview._closeWindow(modelData.id, addr)
                                }
                                onWindowDragStarted: function(payload) {
                                    overview._onWindowDragStarted(modelData.id, payload)
                                }
                                onWindowDragMoved: function(gx, gy) {
                                    overview._onWindowDragMoved(gx, gy)
                                }
                                onWindowDragEnded: function(gx, gy) {
                                    overview._onWindowDragEnded(gx, gy)
                                }
                                onWindowHoverEntered: function(title, gx, gy, w, h) {
                                    overview._onWindowHoverEntered(title, gx, gy, w, h)
                                }
                                onWindowHoverExited: function(title) {
                                    overview._onWindowHoverExited(title)
                                }
                            }
                        }

                        // "+" tile
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
                                readonly property bool isDropTarget:
                                    overview.dragActive && overview.dropTargetKey === "plus"
                                anchors.fill: parent
                                radius: Config.tileRadius
                                color: Config.tileBackground
                                border.width: isDropTarget ? Config.selectedBorderWidth : Config.borderWidth
                                border.color: isDropTarget
                                              ? Config.specialAccent
                                              : (plusHover.hovered ? Config.hoverOutline : Config.panelBorder)
                                Behavior on border.color { ColorAnimation { duration: 90 } }

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

                    Item {
                        anchors.fill: specialGrid
                        z: 5
                        SelectionIndicator { id: specialIndicator }
                    }
                }
            }

            // ---- DRAG GHOST ----
            Item {
                id: dragGhost
                visible: overview.dragActive
                opacity: overview.dragActive ? 0.95 : 0
                Behavior on opacity { NumberAnimation { duration: 100 } }
                z: 1000
                width:  overview.dragW
                height: overview.dragH
                x: overview.dragX
                y: overview.dragY

                Rectangle {
                    id: ghostRect
                    anchors.fill: parent
                    radius: 3
                    color: Config.windowFill
                    border.width: 1
                    border.color: Config.selectedOutline
                    clip: true

                    Loader {
                        anchors.fill: parent
                        active: Config.livePreviews && overview.dragActive && !!overview.dragWl
                        sourceComponent: Item {
                            anchors.fill: parent
                            Image {
                                anchors.fill: parent
                                visible: Config.previewBackground === "wallpaper"
                                         && Config.wallpaperPath.length > 0
                                source: Config.wallpaperPath.length > 0
                                        ? ("file://" + Config.wallpaperPath)
                                        : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: Config.previewBackground !== "wallpaper"
                                         || Config.wallpaperPath.length === 0
                                color: Config.windowFill
                            }
                            ScreencopyView {
                                anchors.fill: parent
                                live: true
                                captureSource: overview.dragWl
                                opacity: hasContent ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 80 } }
                            }
                        }
                    }

                    // Window icon — bottom-left corner badge, declared AFTER
                    // the Loader so it stacks above the live preview. Matches
                    // the same corner-badge style as regular WorkspaceTile
                    // window thumbnails.
                    Image {
                        anchors {
                            left: parent.left
                            bottom: parent.bottom
                            leftMargin: 3
                            bottomMargin: 3
                        }
                        visible: Config.showWindowIcons
                        opacity: Config.windowIconOpacity
                        readonly property real s:
                            Math.min(parent.width, parent.height) * 0.35
                        width:  Math.max(10, Math.min(Config.windowIconMax, s))
                        height: width
                        source: overview.dragIcon || ""
                        sourceSize.width: 32
                        sourceSize.height: 32
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        cache: true
                    }
                }
            }

            // ---- HOVER TOOLTIP ----
            // Floats above everything (z=1001 > drag ghost at z=1000). Anchors
            // to the hovered window box's global position, then maps back into
            // panel coordinates. Wraps text past Config.tooltipMaxWidthFactor *
            // tile width. Clamped to stay inside the panel bounds.
            Item {
                id: tooltipLayer
                anchors.fill: parent
                z: 1001
                visible: overview._ttTitle.length > 0
                Rectangle {
                    id: tooltip
                    radius: 6
                    color: Config.tooltipBg
                    border.width: 1
                    border.color: Config.panelBorder
                    opacity: overview._ttTitle.length > 0 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 90 } }

                    readonly property real maxW:
                        Config.previewWidth * Config.tooltipMaxWidthFactor
                    readonly property real pad: Config.tooltipPadding
                    readonly property real gap: Config.tooltipGap

                    // map the hovered window's top-left into panel coords
                    readonly property real anchorPanelX: {
                        const p = panel.mapFromGlobal(overview._ttAnchorX,
                                                      overview._ttAnchorY)
                        return p.x
                    }
                    readonly property real anchorPanelY: {
                        const p = panel.mapFromGlobal(overview._ttAnchorX,
                                                      overview._ttAnchorY)
                        return p.y
                    }

                    implicitWidth:  Math.min(tooltipText.implicitWidth + pad * 2, maxW)
                    implicitHeight: tooltipText.implicitHeight + pad * 2
                    width:  implicitWidth
                    height: implicitHeight

                    // horizontal: center under hovered window. Tooltip may
                    // overflow the panel — that's intentional, the user wants
                    // to read the full title even on narrow grids.
                    x: anchorPanelX + overview._ttAnchorW / 2 - width / 2

                    // vertical: place above or below per Config.tooltipPosition.
                    // We don't clamp — long titles flowing off-screen is
                    // explicitly allowed.
                    y: Config.tooltipPosition === "below"
                       ? (anchorPanelY + overview._ttAnchorH + gap)
                       : (anchorPanelY - height - gap)

                    Text {
                        id: tooltipText
                        anchors.centerIn: parent
                        width: tooltip.width - tooltip.pad * 2
                        text: overview._ttTitle
                        color: Config.textColor
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Config.labelPixelSize
                        font.family: Config.fontFamily.length > 0
                                     ? Config.fontFamily : Qt.application.font.family
                    }
                }
            }
        }
    }
}
