import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Alt+Tab MRU workspace switcher, event-driven edition.
//
// Like Overview, entries here are workspace identities only — windows are
// looked up live via HyprData.windowsFor(id). The list rebuilds when the
// underlying workspace structure changes; window churn never touches it.
//
// MRU ordering is captured by listening to focusedWorkspaceChanged. The list
// at any moment is "currently-populated workspaces, in MRU order". Empty
// workspaces are filtered out at rebuild time — and we rebuild not just when
// HyprData says workspaces appeared/disappeared, but also when a workspace's
// ListModel becomes empty (last window closed) or non-empty (first window
// opened). That keeps the alt-tab list semantically correct even when no
// structural Hyprland event fires.
Item {
    id: alttab

    // exposed so shell.qml can record workspace history globally
    property var wsHistory: []      // [{id, name}] MRU
    property bool active: false
    property bool armed: false

    // entries are pure identity — { id, name, special, monW, monH }
    property var entries: []
    property int index: 0
    property int _initialDir: 1
    property var _fallbackTarget: null
    property bool _opening: false

    function recordWorkspace(id, name) {
        if (id === undefined || id === null) return
        if (!Config.includeSpecialWorkspaces && HyprData.isSpecial(id, name)) return
        let h = alttab.wsHistory.slice().filter(e => e.id !== id)
        h.unshift({ id: id, name: (name && name.length > 0) ? name : String(id) })
        if (h.length > Config.maxHistory) h = h.slice(0, Config.maxHistory)
        alttab.wsHistory = h
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            const ws = Hyprland.focusedWorkspace
            if (ws) alttab.recordWorkspace(ws.id, ws.name)
        }
    }

    Component.onCompleted: {
        const ws = Hyprland.focusedWorkspace
        if (ws) alttab.recordWorkspace(ws.id, ws.name)
    }

    //=========================================================================
    //  GLOBAL SHORTCUTS
    //=========================================================================
    GlobalShortcut { appid: "hyprtab"; name: "mod";      onReleased: if (alttab.active || alttab.armed) alttab.accept() }
    GlobalShortcut { appid: "hyprtab"; name: "next";     onPressed: alttab.cycle(1) }
    GlobalShortcut { appid: "hyprtab"; name: "prev";     onPressed: alttab.cycle(-1) }
    GlobalShortcut { appid: "hyprtab"; name: "accept";   onPressed: alttab.accept() }
    GlobalShortcut { appid: "hyprtab"; name: "cancel";   onPressed: alttab.cancel() }
    GlobalShortcut { appid: "hyprtab"; name: "closeAll"; onPressed: alttab.closeHighlighted() }

    Timer {
        id: armTimer
        interval: Math.max(0, Config.armDelayMs)
        repeat: false
        onTriggered: {
            if (alttab.armed && !alttab.active) {
                alttab.armed = false
                alttab.active = true
            }
        }
    }

    //=========================================================================
    //  ENTRY REBUILD
    //=========================================================================
    // The entries list contains only populated, non-special (by default)
    // workspaces, in MRU order. We rebuild when:
    //   (a) the alt-tab is opening
    //   (b) HyprData reports workspaces structurally changed
    function _rebuildEntries() {
        let order = [], seen = {}

        // MRU-ordered populated workspaces from history
        for (const h of alttab.wsHistory) {
            if (seen[h.id]) continue
            if (!Config.includeSpecialWorkspaces && HyprData.isSpecial(h.id, h.name)) continue
            const lm = HyprData.windowsFor(h.id)
            if (!lm || lm.count === 0) continue
            seen[h.id] = true
            order.push({ id: h.id, name: h.name })
        }
        // Any other populated workspace not in history
        for (const k in HyprData.workspaces) {
            const idn = parseInt(k)
            const meta = HyprData.workspaces[idn]
            if (seen[idn]) continue
            if (!Config.includeSpecialWorkspaces && meta && meta.special) continue
            const lm = HyprData.windowsFor(idn)
            if (!lm || lm.count === 0) continue
            seen[idn] = true
            order.push({ id: idn, name: meta ? meta.name : String(idn) })
        }

        alttab.entries = order.map(o => {
            const meta = HyprData.workspaces[o.id] || {}
            const monId = (meta.monId !== undefined) ? meta.monId : HyprData.focusedMonitorId
            const mon = HyprData.monitorById[monId] || { w: 16, h: 9 }
            return {
                id: o.id,
                name: o.name || String(o.id),
                special: HyprData.isSpecial(o.id, o.name),
                monW: mon.w || 16,
                monH: mon.h || 9
            }
        })

        // preselect: workspace AFTER current in the list (for forward cycle)
        if (alttab._opening) {
            const n = alttab.entries.length
            const curId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : null
            let curIdx = -1
            for (let i = 0; i < n; i++)
                if (alttab.entries[i].id === curId) { curIdx = i; break }
            if (n === 0)                       alttab.index = 0
            else if (alttab._initialDir > 0)   alttab.index = (curIdx >= 0) ? ((curIdx + 1) % n) : 0
            else                               alttab.index = (curIdx >= 0) ? ((curIdx - 1 + n) % n) : (n - 1)
            alttab._opening = false
        }
        if (alttab.index >= alttab.entries.length)
            alttab.index = Math.max(0, alttab.entries.length - 1)
    }

    // Rebuild on structural workspace changes. Also on geometry sync completion
    // (first bootstrap, or any time we missed events) — this is cheap and the
    // rebuild itself is a no-op if nothing semantically changed.
    Connections {
        target: HyprData
        function onWorkspacesChanged() { alttab._rebuildEntries() }
        function onUpdated() {
            if (alttab.active || alttab.armed) alttab._rebuildEntries()
        }
    }

    function _quickFallbackTarget(dir) {
        const h = alttab.wsHistory
        if (h.length < 2) return null
        return dir > 0 ? h[1] : h[h.length - 1]
    }

    function cycle(dir) {
        if (!alttab.active && !alttab.armed) {
            alttab._opening = true
            alttab._initialDir = dir
            win.screen = root.focusedScreen() || win.screen
            alttab._rebuildEntries()
            alttab._fallbackTarget = alttab._quickFallbackTarget(dir)
            if (Config.armDelayMs <= 0) {
                alttab.active = true
            } else {
                alttab.armed = true
                armTimer.interval = Config.armDelayMs
                armTimer.restart()
            }
        } else if (alttab.armed && !alttab.active) {
            if (Config.armSecondTapShows) {
                armTimer.stop()
                alttab.armed = false
                alttab.active = true
            }
            const n = alttab.entries.length
            if (n > 0) alttab.index = (alttab.index + dir + n) % n
        } else {
            const n = alttab.entries.length
            if (n === 0) return
            alttab.index = (alttab.index + dir + n) % n
        }
    }

    function accept() {
        if (alttab.entries.length > 0) {
            const e = alttab.entries[alttab.index]
            if (e && e.id !== undefined) HyprData.dispatchSwitch(e.id, e.name)
        } else if (alttab._fallbackTarget) {
            HyprData.dispatchSwitch(alttab._fallbackTarget.id, alttab._fallbackTarget.name)
        }
        armTimer.stop()
        alttab.armed = false
        alttab.active = false
        alttab._fallbackTarget = null
    }

    function cancel() {
        armTimer.stop()
        alttab.armed = false
        alttab.active = false
        alttab._fallbackTarget = null
    }

    //=========================================================================
    //  SELECTION INDICATOR
    //=========================================================================
    property var tilesByIndex: ({})

    function _refreshIndicator() {
        if (!alttab.active) { indicator.hide(); return }
        const n = alttab.entries.length
        if (n === 0) { indicator.hide(); return }
        const tile = alttab.tilesByIndex[alttab.index]
        const e = alttab.entries[alttab.index] || {}
        if (tile) indicator.moveTo(tile, !!e.special)
        else indicator.hide()
    }

    onIndexChanged:   alttab._refreshIndicator()
    onActiveChanged:  alttab._refreshIndicator()
    onEntriesChanged: Qt.callLater(alttab._refreshIndicator)

    //=========================================================================
    //  DELETE-KEY: close every window on highlighted workspace
    //=========================================================================
    // Just dispatches the close batch. The closewindow events update HyprData,
    // which removes the rows from the workspace's ListModel; the tile reflects
    // it live. Once empty, the workspace stays in entries until next open
    // (when the filter drops it). User keeps cycling fine.
    function closeHighlighted() {
        if (!alttab.active && !alttab.armed) return
        if (alttab.entries.length === 0) return
        const e = alttab.entries[alttab.index]
        if (!e) return
        const lm = HyprData.windowsFor(e.id)
        if (!lm || lm.count === 0) return

        let cmds = []
        for (let i = 0; i < lm.count; i++) {
            const w = lm.get(i)
            if (w.address) cmds.push("dispatch closewindow address:" + w.address)
        }
        if (cmds.length === 0) return
        batchProc.command = ["hyprctl", "--batch", cmds.join(";")]
        batchProc.running = true
    }

    Process { id: batchProc }

    //=========================================================================
    //  UI
    //=========================================================================
    PanelWindow {
        id: win
        visible: alttab.active
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hyprtab"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Config.backdropColor
            opacity: Config.altTabBackdropOpacity
            MouseArea { anchors.fill: parent; onClicked: alttab.cancel() }
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            radius: Config.panelRadius
            color: Config.altTabPanelBg
            border.width: Config.borderWidth
            border.color: Config.panelBorder
            implicitWidth:  Math.max(grid.implicitWidth  + Config.panelPadding * 2,
                                     emptyHint.visible ? emptyHint.implicitWidth  + 56 : 0)
            implicitHeight: Math.max(grid.implicitHeight + Config.panelPadding * 2,
                                     emptyHint.visible ? emptyHint.implicitHeight + 36 : 0)

            Grid {
                id: grid
                anchors.centerIn: parent
                columns: Math.max(1, Math.min(alttab.entries.length, Config.altTabMaxColumns))
                spacing: Config.tileSpacing

                Repeater {
                    model: alttab.entries
                    delegate: WorkspaceTile {
                        required property var modelData
                        required property int index
                        wsId: modelData.id
                        wsName: modelData.name
                        special: modelData.special
                        windowsModel: HyprData.windowsFor(modelData.id)
                        monW: modelData.monW
                        monH: modelData.monH
                        windowHoverHighlight: false
                        // Only stream while the alt-tab is visible — armed
                        // state (before the arm timer expires) doesn't render
                        // tiles, so previews wouldn't be visible anyway.
                        previewsActive: alttab.active
                        Component.onCompleted: {
                            let m = alttab.tilesByIndex
                            m[index] = this
                            alttab.tilesByIndex = m
                            if (index === alttab.index) Qt.callLater(alttab._refreshIndicator)
                        }
                        Component.onDestruction: {
                            let m = alttab.tilesByIndex
                            if (m[index] === this) { delete m[index]; alttab.tilesByIndex = m }
                        }
                        onTileClicked: { alttab.index = index; alttab.accept() }
                    }
                }
            }

            // floating selection ring as a sibling of the grid
            Item {
                anchors.fill: grid
                z: 5
                SelectionIndicator {
                    id: indicator
                    moveDuration: 180
                    fadeDuration: 120
                    showInnerTint: true
                }
            }

            Text {
                id: emptyHint
                anchors.centerIn: parent
                visible: alttab.entries.length === 0
                text: "No other populated workspaces"
                color: Config.textColor
                font.pixelSize: Config.labelPixelSize
                font.family: Config.fontFamily.length > 0
                             ? Config.fontFamily : Qt.application.font.family
            }
        }
    }
}
