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
    // Set the first time the `mod` global shortcut delivers a press. If it
    // never does — which is the case when the compositor doesn't match the
    // modifier bind — we must not trust modShortcut.pressed, because a
    // permanently-false `pressed` would make the arm timer commit on every
    // single Alt+Tab and the panel would never appear at all.
    property bool _modSeen: false

    GlobalShortcut { id: modShortcut
                     appid: "hyprtab"; name: "mod"
                     onPressed: alttab._modSeen = true
                     onReleased: if (alttab.active || alttab.armed) alttab.accept() }
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
            if (!alttab.armed || alttab.active) return

            // If the `mod` shortcut is actually working, we can tell whether
            // Alt is still physically down. Already up means the user did a
            // quick tap and the release raced this timer — commit silently
            // rather than popping the panel open with nothing to dismiss it.
            //
            // Guarded on _modSeen: only meaningful once we've observed at
            // least one press from this shortcut. Without that guard, a
            // non-delivering shortcut reads as "never pressed" and we'd
            // commit on every arm expiry.
            if (alttab._modSeen && !modShortcut.pressed) {
                alttab.accept()
                return
            }

            alttab.armed = false
            alttab.active = true
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
        // Idempotent: only commit if we're actually up or arming. Guards
        // against a second release event (e.g. if both a bare and a
        // modifier-qualified bind match the same key) or the released signal
        // racing the arm timer — without this, either could dispatch the
        // workspace switch twice.
        if (!alttab.active && !alttab.armed) return

        armTimer.stop()
        alttab.armed = false
        alttab.active = false

        if (alttab.entries.length > 0) {
            const e = alttab.entries[alttab.index]
            if (e && e.id !== undefined) HyprData.dispatchSwitch(e.id, e.name)
        } else if (alttab._fallbackTarget) {
            HyprData.dispatchSwitch(alttab._fallbackTarget.id,
                                    alttab._fallbackTarget.name)
        }
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
            if (w.address) cmds.push(HyprData.batchCloseWindowArg(w.address))
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
        // Mapped during the arm phase as well as when shown.
        //
        // The commit-on-Alt-release path that actually works is the
        // Keys.onReleased handler below, which needs this surface focused.
        // When only the visible panel was mapped, releasing Alt inside the
        // arm window hit nothing: no focus, no key handler, and the
        // `hyprtab:mod` global shortcut doesn't reliably deliver a release
        // edge for a modifier key. So a quick tap-and-release opened the
        // panel and left it sitting there.
        //
        // Mapping during arming closes that gap. Nothing is drawn — the
        // backdrop and panel below are gated on `active`, so the arm window
        // stays visually silent and the anti-flash behaviour is preserved.
        //
        // The surface is mapped PERMANENTLY, not just while armed/active.
        // Creating a layer surface and then acquiring keyboard focus takes a
        // compositor roundtrip; for a fast Alt+Tab tap the release can beat
        // that and the commit is lost. Keeping the surface alive means arming
        // only has to flip keyboardFocus, which is a single roundtrip instead
        // of surface-create-then-focus.
        //
        // While idle it's completely inert: nothing is drawn (every child is
        // gated on `active`), keyboard focus is None, and `mask` is an empty
        // region so it swallows no pointer input either.
        visible: true
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hyprtab"

        // Empty region == accepts no pointer input. Applied whenever we're
        // neither armed nor showing, so the always-mapped overlay never eats
        // clicks meant for the desktop underneath.
        Region { id: noInputRegion }
        mask: (alttab.active || alttab.armed) ? null : noInputRegion

        // Focus from the moment we arm, so the Alt release is caught whether
        // or not the panel has appeared yet. Compositor binds are evaluated
        // before keys reach clients, so ALT+Tab still reaches the `next`
        // global shortcut — cycling is unaffected.
        WlrLayershell.keyboardFocus: (alttab.active || alttab.armed)
                                     ? WlrKeyboardFocus.Exclusive
                                     : WlrKeyboardFocus.None

        Item {
            anchors.fill: parent
            focus: alttab.active || alttab.armed

            // Commit on Alt release — this is the release-to-commit path that
            // the global shortcut was supposed to provide.
            Keys.onReleased: function(event) {
                if (event.key === Qt.Key_Alt
                    || event.key === Qt.Key_Meta
                    || event.key === Qt.Key_AltGr) {
                    event.accepted = true
                    if (alttab.active || alttab.armed) alttab.accept()
                }
            }

            // Escape / Enter / Delete as direct keys, so they work without
            // needing a global shortcut round-trip.
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    alttab.cancel(); event.accepted = true
                } else if (event.key === Qt.Key_Return
                           || event.key === Qt.Key_Enter) {
                    alttab.accept(); event.accepted = true
                } else if (event.key === Qt.Key_Delete) {
                    alttab.closeHighlighted(); event.accepted = true
                }
            }
        }

        // Gated on `active`, not on the window being mapped: during the arm
        // phase the surface exists (to hold focus) but must draw nothing.
        Rectangle {
            anchors.fill: parent
            visible: alttab.active
            color: Config.backdropColor
            opacity: Config.altTabBackdropOpacity
            MouseArea { anchors.fill: parent; onClicked: alttab.cancel() }
        }

        Rectangle {
            id: panel
            visible: alttab.active
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
