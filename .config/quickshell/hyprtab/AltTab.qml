import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// MRU workspace switcher driven by Alt+Tab. Held-modifier behavior: Tab to
// advance, release Alt to commit. Anti-flash arm timer hides the UI for a
// short window so quick taps dispatch silently.
Item {
    id: alttab

    // exposed so shell.qml can record workspace history globally
    property var wsHistory: []      // [{id, name}] MRU
    property bool active: false
    property bool armed: false

    property var entries: []        // [{id, name, special, windows[], monW, monH}]
    property int index: 0
    property int _initialDir: 1
    property var _fallbackTarget: null

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
        HyprData.refresh()
    }

    //=========================================================================
    //  GLOBAL SHORTCUTS  (Hyprland triggers via `global, hyprtab:<name>`)
    //=========================================================================
    GlobalShortcut { appid: "hyprtab"; name: "mod";    onReleased: if (alttab.active || alttab.armed) alttab.accept() }
    GlobalShortcut { appid: "hyprtab"; name: "next";   onPressed: alttab.cycle(1) }
    GlobalShortcut { appid: "hyprtab"; name: "prev";   onPressed: alttab.cycle(-1) }
    GlobalShortcut { appid: "hyprtab"; name: "accept"; onPressed: alttab.accept() }
    GlobalShortcut { appid: "hyprtab"; name: "cancel"; onPressed: alttab.cancel() }

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

    // Refresh listener: when HyprData updates, rebuild our filtered entry list.
    Connections {
        target: HyprData
        function onUpdated() { alttab._rebuildEntries() }
    }

    function _rebuildEntries() {
        // entries from MRU history first, but ONLY for currently-populated workspaces
        let order = [], seen = {}
        for (const h of alttab.wsHistory) {
            if (seen[h.id]) continue
            if (!Config.includeSpecialWorkspaces && HyprData.isSpecial(h.id, h.name)) continue
            if (!HyprData.byWs[h.id]) continue   // empty workspaces don't enter cycle
            seen[h.id] = true
            order.push({ id: h.id, name: h.name })
        }
        // any other populated workspace not yet in history
        for (const k in HyprData.byWs) {
            const idn = parseInt(k)
            const meta = HyprData.wsMeta[idn]
            if (seen[idn]) continue
            if (!Config.includeSpecialWorkspaces && meta && meta.special) continue
            seen[idn] = true
            order.push({ id: idn, name: meta ? meta.name : String(idn) })
        }

        alttab.entries = order.map(o => {
            const wins = HyprData.byWs[o.id] || []
            const meta = HyprData.wsMeta[o.id] || {}
            const monId = (meta.monId !== undefined) ? meta.monId : HyprData.focusedMonitorId
            const mon = HyprData.monitorById[monId] || { w: 16, h: 9 }
            return {
                id: o.id, name: o.name || String(o.id),
                special: HyprData.isSpecial(o.id, o.name),
                windows: wins, monW: mon.w || 16, monH: mon.h || 9
            }
        })

        // preselect: workspace AFTER current in the populated list
        if (alttab._opening) {
            const n = alttab.entries.length
            const curId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : null
            let curIdx = -1
            for (let i = 0; i < n; i++)
                if (alttab.entries[i].id === curId) { curIdx = i; break }
            if (n === 0)                 alttab.index = 0
            else if (alttab._initialDir > 0)
                alttab.index = (curIdx >= 0) ? ((curIdx + 1) % n) : 0
            else
                alttab.index = (curIdx >= 0) ? ((curIdx - 1 + n) % n) : (n - 1)
            alttab._opening = false
        }
        if (alttab.index >= alttab.entries.length)
            alttab.index = Math.max(0, alttab.entries.length - 1)
    }
    property bool _opening: false

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
            HyprData.refresh()
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

    // Map of grid index -> tile Item, populated by each delegate on completion
    // and used by the floating SelectionIndicator to target the right tile.
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
            opacity: Config.backdropOpacity
            MouseArea { anchors.fill: parent; onClicked: alttab.cancel() }
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
                        windows: modelData.windows
                        monW: modelData.monW
                        monH: modelData.monH
                        Component.onCompleted: {
                            // register self so the floating indicator can locate us
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

            // The floating selection ring is a SIBLING of the grid, not a child.
            // Putting it inside the Grid would make the Grid layout reserve a
            // cell for it past the last tile, producing phantom rows and bogus
            // animation endpoints. Anchoring to the grid's bounds keeps the
            // indicator in the grid's coordinate space so it can read raw
            // target.x / target.y directly.
            Item {
                id: indicatorOverlay
                anchors.fill: grid
                z: 5
                SelectionIndicator {
                    id: indicator
                    moveDuration: 180   // snappier for alt-tab
                    fadeDuration: 120
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
