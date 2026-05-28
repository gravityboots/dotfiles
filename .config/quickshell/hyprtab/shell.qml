//=============================================================================
//  hyprtab — a standalone Quickshell Alt+Tab WORKSPACE switcher for Hyprland
//
//  Hold Alt + tap Tab to cycle through workspaces in most-recently-used order;
//  release Alt to switch to the highlighted workspace. Each workspace is drawn
//  as a mini-desktop wireframe showing where its windows are laid out. Styled
//  to match the Noctalia launcher.
//
//  Run with:   qs -c hyprtab
//  Lives at:   ~/.config/quickshell/hyprtab/shell.qml
//
//  Input is driven entirely by Hyprland GlobalShortcuts (see hyprtab.conf),
//  so this overlay never needs keyboard focus. Workspace MRU history is tracked
//  internally by watching the focused workspace — no external daemon required.
//=============================================================================

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    //=========================================================================
    //  CONFIG  — edit these. Colors are prefilled with the Noctalia dark theme.
    //=========================================================================

    // --- the four colors you asked to control ---
    property color backgroundColor:    "#010409"   // mSurface — panel background
    property color selectedBackground: "#58a6ff"   // mPrimary — tint wash on selected tile
    property color textColor:          "#c9d1d9"    // mOnSurface — labels
    property color selectedOutline:    "#58a6ff"    // mPrimary — outline of selected tile

    // --- secondary colors (Noctalia-matched defaults) ---
    property color panelBorder:        "#30363d"    // mOutline — panel + tile borders
    property color tileBackground:     "#161b22"    // mSurfaceVariant — the mini-desktop "screen"
    property color hoverOutline:       "#8b949e"    // mOnSurfaceVariant — tile hover border
    property color windowFill:         "#21262d"    // mHover — window box fill
    property color windowBorder:       "#484f58"    // window box outline (wireframe)
    property color selectedTextColor:  "#c9d1d9"    // mOnSurface — label on selected tile
    property color backdropColor:      "#010409"    // dim behind the panel

    // --- opacities ---
    property real backgroundOpacity:   0.85   // panel fill
    property real backdropOpacity:     0.15   // full-screen dim
    property real selectedTint:        0.15   // strength of selectedBackground wash on selection

    // --- geometry ---
    property real panelRadius:         20
    property real tileRadius:          12
    property real previewWidth:        250    // FIXED width of each tile — tiles never shrink
    property real previewInset:        4      // padding between tile edge and the mini-desktop
    property real tileSpacing:         8
    property real panelPadding:        12
    property real borderWidth:         1
    property real selectedBorderWidth: 2
    property int  maxColumns:          5      // up to this many per row, then wrap to a new row

    // --- window wireframe / previews ---
    property bool livePreviews:        true   // show real window thumbnails inside each box
    property bool liveCapture:         false  // false = snapshot per open (light); true = live feed
    property bool showWindowIcons:     false   // app icon (also the fallback when a preview fails)
    property real windowIconMax:       30     // cap on the icon size drawn inside a window box

    // --- type ---
    property string fontFamily:        "GeistMono Nerd Font Mono"     // "" = system default; e.g. "Inter", "Cantarell"
    property real   labelPixelSize:    13

    // --- behavior ---
    property bool   skipUnmapped:             true
    property bool   includeSpecialWorkspaces: false   // special workspaces stay out of the stack
    property int    maxHistory:               12
    property string fallbackIcon:             "application-x-executable"
    property string splitToken:               "__HYPRTAB_SPLIT__"

    //=========================================================================
    //  STATE
    //=========================================================================
    property bool active: false
    property var  wsHistory: []   // [{id, name}] most-recent first  (MRU source of truth)
    property var  entries: []     // built on open: [{id, name, special, windows[], monW, monH}]
    property int  index: 0
    property int  _initialDir: 1
    property bool _opening: false

    //=========================================================================
    //  HELPERS
    //=========================================================================
    function isSpecial(id, name) {
        if (id !== undefined && id !== null && id < 0) return true;
        return (typeof name === "string") && name.indexOf("special") === 0;
    }

    //=========================================================================
    //  WORKSPACE MRU TRACKING  (continuous, from launch)
    //=========================================================================
    function recordWorkspace(id, name) {
        if (id === undefined || id === null) return;
        if (!root.includeSpecialWorkspaces && root.isSpecial(id, name)) return;
        let h = root.wsHistory.slice().filter(e => e.id !== id);
        h.unshift({ id: id, name: (name && name.length > 0) ? name : String(id) });
        if (h.length > root.maxHistory) h = h.slice(0, root.maxHistory);
        root.wsHistory = h;
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            const ws = Hyprland.focusedWorkspace;
            if (ws) root.recordWorkspace(ws.id, ws.name);
        }
    }

    Component.onCompleted: {
        const ws = Hyprland.focusedWorkspace;
        if (ws) root.recordWorkspace(ws.id, ws.name);
    }

    //=========================================================================
    //  GLOBAL SHORTCUTS  (Hyprland triggers these via `global, hyprtab:<name>`)
    //=========================================================================
    GlobalShortcut { appid: "hyprtab"; name: "mod";    onReleased: if (root.active) root.accept() }
    GlobalShortcut { appid: "hyprtab"; name: "next";   onPressed: root.cycle(1) }
    GlobalShortcut { appid: "hyprtab"; name: "prev";   onPressed: root.cycle(-1) }
    GlobalShortcut { appid: "hyprtab"; name: "accept"; onPressed: root.accept() }
    GlobalShortcut { appid: "hyprtab"; name: "cancel"; onPressed: root.cancel() }

    //=========================================================================
    //  DATA  — clients + monitors fetched fresh each time the switcher opens.
    //=========================================================================
    Process {
        id: dataProc
        command: ["sh", "-c",
                  "hyprctl clients -j; printf '" + root.splitToken + "'; hyprctl monitors -j"]
        stdout: StdioCollector {
            id: dataOut
            onStreamFinished: root.populate(dataOut.text)
        }
    }

    //=========================================================================
    //  LOGIC
    //=========================================================================
    function focusedScreen() {
        const mon = Hyprland.focusedMonitor;
        if (mon)
            for (let i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === mon.name)
                    return Quickshell.screens[i];
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    function resolveIcon(cls) {
        if (!cls || cls.length === 0) return Quickshell.iconPath(root.fallbackIcon);
        const entry = DesktopEntries.heuristicLookup(cls);
        if (entry && entry.icon && entry.icon.length > 0)
            return Quickshell.iconPath(entry.icon, root.fallbackIcon);
        return Quickshell.iconPath(cls.toLowerCase(), root.fallbackIcon);
    }

    function populate(text) {
        const parts = text.split(root.splitToken);
        let clients = [], mons = [];
        try { clients = JSON.parse(parts[0]); } catch (e) { clients = []; }
        try { mons    = JSON.parse(parts[1]); } catch (e) { mons = []; }

        if (root.skipUnmapped) clients = clients.filter(c => c.mapped !== false);
        clients = clients.filter(c => c.size && c.size[0] > 0 && c.size[1] > 0);

        // monitor map: id -> geometry (for normalizing window coords to 0..1)
        let mmap = {};
        for (const m of mons) mmap[m.id] = { x: m.x, y: m.y, w: m.width, h: m.height };
        const fm = Hyprland.focusedMonitor;
        const fmId = fm ? fm.id : (mons.length > 0 ? mons[0].id : 0);

        function norm(c) {
            const mon = mmap[c.monitor] || mmap[fmId] || { x: 0, y: 0, w: 1920, h: 1080 };
            const clamp = v => Math.max(0, Math.min(1, v));
            return {
                rx: clamp((c.at[0]   - mon.x) / mon.w),
                ry: clamp((c.at[1]   - mon.y) / mon.h),
                rw: clamp( c.size[0]          / mon.w),
                rh: clamp( c.size[1]          / mon.h)
            };
        }

        // map window address -> live Wayland capture handle (for ScreencopyView).
        // Hyprland.toplevels gives us both the address (via lastIpcObject) and the
        // wayland handle that ScreencopyView can capture.
        let handleByAddr = {};
        const tls = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (const t of tls) {
            const obj = t.lastIpcObject;
            const addr = obj ? obj.address : null;
            if (addr && t.wayland) handleByAddr[addr] = t.wayland;
        }

        // group windows by workspace id
        let byWs = {}, wsMon = {}, wsName = {};
        for (const c of clients) {
            const w = c.workspace || {};
            const wid = (w.id !== undefined) ? w.id : 0;
            if (!root.includeSpecialWorkspaces && root.isSpecial(wid, w.name)) continue;
            if (!byWs[wid]) {
                byWs[wid] = [];
                wsMon[wid] = c.monitor;
                wsName[wid] = (w.name && w.name.length > 0) ? w.name : String(wid);
            }
            const r = norm(c);
            byWs[wid].push({
                rx: r.rx, ry: r.ry, rw: r.rw, rh: r.rh,
                floating: !!c.floating,
                icon: root.resolveIcon(c.class || c.initialClass || ""),
                wl: handleByAddr[c.address] || null
            });
        }

        // build the ordered tile list: MRU history first, then any other
        // workspaces that currently hold windows. EMPTY workspaces are skipped
        // entirely — only populated workspaces ever enter the switch stack.
        let order = [], seen = {};
        for (const h of root.wsHistory) {
            if (seen[h.id]) continue;
            if (!root.includeSpecialWorkspaces && root.isSpecial(h.id, h.name)) continue;
            if (!byWs[h.id]) continue;        // <-- no windows right now → not in the stack
            seen[h.id] = true;
            order.push({ id: h.id, name: h.name });
        }
        for (const k in byWs) {
            const idn = parseInt(k);
            if (!seen[idn]) { seen[idn] = true; order.push({ id: idn, name: wsName[k] }); }
        }

        root.entries = order.map(o => {
            const wins = byWs[o.id] || [];
            const monId = (wins.length > 0) ? wsMon[o.id] : fmId;
            const mon = mmap[monId] || mmap[fmId] || { w: 16, h: 9 };
            return {
                id: o.id,
                name: o.name || String(o.id),
                special: root.isSpecial(o.id, o.name),
                windows: wins,
                monW: mon.w || 16,
                monH: mon.h || 9
            };
        });

        if (root._opening) {
            const n = root.entries.length;
            // find where the CURRENT workspace sits in the populated list.
            // if we're on an empty workspace it won't be listed (curIdx = -1),
            // in which case "previous" is simply the most-recent populated one.
            const curId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : null;
            let curIdx = -1;
            for (let i = 0; i < n; i++)
                if (root.entries[i].id === curId) { curIdx = i; break; }

            if (n === 0)
                root.index = 0;
            else if (root._initialDir > 0)
                root.index = (curIdx >= 0) ? ((curIdx + 1) % n) : 0;
            else
                root.index = (curIdx >= 0) ? ((curIdx - 1 + n) % n) : (n - 1);
            root._opening = false;
        }
        if (root.index >= root.entries.length)
            root.index = Math.max(0, root.entries.length - 1);
    }

    function cycle(dir) {
        if (!root.active) {
            root._opening = true;
            root._initialDir = dir;
            win.screen = root.focusedScreen() || win.screen;
            dataProc.running = true;       // populate() fills entries + sets index
            root.active = true;
        } else {
            const n = root.entries.length;
            if (n === 0) return;
            root.index = (root.index + dir + n) % n;
        }
    }

    function dispatchWorkspace(e) {
        if (root.isSpecial(e.id, e.name)) {
            const idx = (e.name || "").indexOf(":");
            const sub = idx >= 0 ? e.name.substring(idx + 1) : "";
            Hyprland.dispatch(sub.length > 0 ? ("togglespecialworkspace " + sub)
                                             : "togglespecialworkspace");
        } else {
            Hyprland.dispatch("workspace " + e.id);
        }
    }

    function accept() {
        if (root.active && root.entries.length > 0) {
            const e = root.entries[root.index];
            if (e && e.id !== undefined) root.dispatchWorkspace(e);
        }
        root.active = false;
    }

    function cancel() { root.active = false; }

    //=========================================================================
    //  UI
    //=========================================================================
    PanelWindow {
        id: win
        visible: root.active
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hyprtab"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // dim backdrop + click-outside-to-cancel
        Rectangle {
            anchors.fill: parent
            color: root.backdropColor
            opacity: root.backdropOpacity
            MouseArea { anchors.fill: parent; onClicked: root.cancel() }
        }

        // centered panel
        Rectangle {
            id: panel
            anchors.centerIn: parent
            radius: root.panelRadius
            color: root.backgroundColor
            opacity: root.backgroundOpacity
            border.width: root.borderWidth
            border.color: root.panelBorder
            implicitWidth:  grid.implicitWidth  + root.panelPadding * 2
            implicitHeight: grid.implicitHeight + root.panelPadding * 2

            // up to maxColumns tiles per row; extra rows stack downward.
            // tiles are a fixed previewWidth, so they never shrink.
            Grid {
                id: grid
                anchors.centerIn: parent
                columns: Math.max(1, Math.min(root.entries.length, root.maxColumns))
                spacing: root.tileSpacing

                Repeater {
                    model: root.entries

                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.index
                        readonly property real innerW: root.previewWidth - root.previewInset * 2
                        readonly property real innerH:
                            Math.max(60, innerW * (modelData.monH / Math.max(1, modelData.monW)))

                        width: root.previewWidth
                        height: innerH + root.previewInset * 2     // no label row → no space below
                        radius: root.tileRadius
                        color: root.tileBackground
                        border.width: selected ? root.selectedBorderWidth : root.borderWidth
                        border.color: selected ? root.selectedOutline
                                    : (hover.hovered ? root.hoverOutline : root.panelBorder)
                        Behavior on border.color { ColorAnimation { duration: 90 } }

                        // mini-desktop
                        Item {
                            id: screen
                            x: root.previewInset; y: root.previewInset
                            width: tile.innerW; height: tile.innerH
                            clip: true

                            Repeater {
                                model: tile.modelData.windows
                                delegate: Rectangle {
                                    required property var modelData
                                    x: modelData.rx * screen.width
                                    y: modelData.ry * screen.height
                                    width:  Math.max(6, modelData.rw * screen.width)
                                    height: Math.max(6, modelData.rh * screen.height)
                                    radius: 3
                                    color: root.windowFill
                                    border.width: 1
                                    border.color: root.windowBorder
                                    clip: true

                                    // fallback: app icon (shown until/unless a preview is ready)
                                    Image {
                                        anchors.centerIn: parent
                                        visible: root.showWindowIcons
                                        readonly property real s:
                                            Math.min(parent.width, parent.height) * 0.55
                                        width:  Math.max(8, Math.min(root.windowIconMax, s))
                                        height: width
                                        source: modelData.icon
                                        sourceSize.width: width
                                        sourceSize.height: width
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        smooth: true
                                    }

                                    // live window thumbnail (covers the icon when ready)
                                    Loader {
                                        anchors.fill: parent
                                        active: root.livePreviews && !!modelData.wl
                                        sourceComponent: ScreencopyView {
                                            anchors.fill: parent
                                            live: root.liveCapture
                                            captureSource: modelData.wl
                                            opacity: hasContent ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                        }
                                    }
                                }
                            }

                            // empty-workspace hint
                            Text {
                                anchors.centerIn: parent
                                visible: tile.modelData.windows.length === 0
                                text: "empty"
                                color: root.textColor
                                opacity: 0.4
                                font.pixelSize: root.labelPixelSize
                                font.family: root.fontFamily.length > 0
                                             ? root.fontFamily : Qt.application.font.family
                            }

                            // selection wash (honors your selectedBackground color)
                            Rectangle {
                                anchors.fill: parent
                                color: root.selectedBackground
                                opacity: tile.selected ? root.selectedTint : 0
                                Behavior on opacity { NumberAnimation { duration: 90 } }
                            }
                        }

                        // workspace number badge — corner overlay, no space reserved under tile
                        Rectangle {
                            x: root.previewInset + 4
                            y: root.previewInset + 4
                            width: wsLabel.implicitWidth + 12
                            height: wsLabel.implicitHeight + 5
                            radius: 7
                            color: root.backgroundColor
                            opacity: 0.78
                            Text {
                                id: wsLabel
                                anchors.centerIn: parent
                                text: tile.modelData.special
                                      ? ("\u2605 " + tile.modelData.name)   // ★ marks a special ws
                                      : tile.modelData.name
                                color: tile.selected ? root.selectedTextColor : root.textColor
                                font.bold: tile.selected
                                font.pixelSize: root.labelPixelSize
                                font.family: root.fontFamily.length > 0
                                             ? root.fontFamily : Qt.application.font.family
                            }
                        }

                        // click a tile to jump straight to that workspace (kept on top)
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.index = tile.index; root.accept(); }
                        }
                    }
                }
            }

            // overall empty guard
            Text {
                anchors.centerIn: parent
                visible: root.entries.length === 0
                text: "No workspaces"
                color: root.textColor
                font.pixelSize: root.labelPixelSize
            }
        }
    }
}
