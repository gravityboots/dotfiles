pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Event-driven model for hyprtab.
//
// Architecture:
//   - Initial state is pulled once from `hyprctl clients -j` + `hyprctl monitors -j`.
//   - All subsequent mutations are driven by Hyprland.rawEvent (socket2 events).
//   - Per-workspace `ListModel`s are address-stable: opening/closing/moving a
//     window touches at most one row in one ListModel (or one in each of two),
//     leaving every other WorkspaceTile delegate untouched — no flash.
//   - Geometry data (rx/ry/rw/rh) isn't carried by events, so any event that
//     changes window layout (open, move, fullscreen, configreload) triggers a
//     debounced address-keyed sync against fresh hyprctl output. That sync only
//     `set()`s rows whose geometry actually changed; unchanged rows keep their
//     ScreencopyView intact.
//
// Public API:
//   windowsFor(wsId)   -> ListModel for a workspace, stable reference, created lazily
//   workspaces         -> { wsId -> { id, name, special, monId } }
//   monitorById        -> { monId -> { id, name, x, y, w, h } }
//   monitorSpecial     -> { monId -> name of currently-overlaid special, or "" }
//   focusedMonitorId   -> int
//   handleByAddr       -> { address -> wayland capture handle }
//   isSpecial(id,name) -> bool
//   specialName(name)  -> "stash" from "special:stash"
//   resolveIcon(...)   -> icon path
//   dispatchSwitch(id, name) -> switch to workspace (handles special overlay correctly)
//   createNewSpecial() -> opens a new "stash"/"stash-2"/... special
//   openSpecials()     -> array of currently-open special names
QtObject {
    id: data

    //=========================================================================
    //  PUBLIC STATE
    //=========================================================================
    property var workspaces:       ({})   // wsId -> { id, name, special, monId }
    property var monitorById:      ({})   // monId -> { id, name, x, y, w, h }
    property var monitorSpecial:   ({})   // monId -> name (without "special:") or ""
    property int focusedMonitorId: 0
    property var handleByAddr:     ({})   // address -> wayland capture handle

    // NOTE on signals:
    //   `workspaces` is a `property var`, so QML auto-generates a
    //   `workspacesChanged` signal that fires on reassignment. Consumers
    //   should write `Connections { target: HyprData; function onWorkspacesChanged() {...} }`
    //   to react to structural changes. We deliberately do NOT declare an
    //   explicit `signal workspacesChanged()` — that would clash with the
    //   auto-generated property-change signal.
    //
    //   Likewise we don't override change signals for `workspaces`,
    //   `monitorSpecial`, `handleByAddr`, etc. They're plain properties; the
    //   auto-signal does the job.
    signal windowMoved(string address, int fromWs, int toWs)
    signal windowClosed(string address)

    // No-op kept for back-compat. Internally just kicks a geometry sync, in
    // case any events were missed between the last sync and now. Event-driven
    // consumers never need to call this; the model is always live.
    function refresh() { data._queueGeomSync() }

    // Emitted when geometry sync completes (initial bootstrap or post-event
    // re-sync). Most consumers should NOT listen — bind to per-ws ListModels.
    signal updated()

    //=========================================================================
    //  PUBLIC API
    //=========================================================================
    function windowsFor(wsId) {
        const key = wsId.toString()
        if (!data._wsModels[key]) {
            const lm = _wsModelComponent.createObject(data)
            let m = data._wsModels
            m[key] = lm
            data._wsModels = m
        }
        return data._wsModels[key]
    }

    function isSpecial(id, name) {
        if (id !== undefined && id !== null && id < 0) return true
        return (typeof name === "string") && name.indexOf("special") === 0
    }

    function specialName(fullName) {
        if (typeof fullName !== "string") return ""
        const idx = fullName.indexOf(":")
        return idx >= 0 ? fullName.substring(idx + 1) : ""
    }

    // Class -> resolved icon path. Keyed by lowercased class string. Cleared
    // never — at most a few dozen entries for a typical session, and the
    // result of Quickshell.iconPath is just a small URL string.
    property var _iconCache: ({})

    function resolveIcon(cls, fallback) {
        // Build a list of candidate icon names from best to worst:
        //   1. Heuristic desktop-entry lookup (matches "VSCodium" → codium icon)
        //   2. The class string itself, lowercased
        //   3. Common transformations: strip dotted prefix (org.gnome.Nautilus
        //      → nautilus), substitute hyphens
        // For each candidate we use Quickshell.iconPath(name, true) which
        // returns an empty string if the icon doesn't actually exist in the
        // theme — that lets us walk to the next candidate without rendering
        // a purple/black missing-texture placeholder. Only the final fallback
        // uses the (name, fallback) variant so we always end up with SOME
        // valid path. Empty cls short-circuits to fallback directly.
        if (!cls || cls.length === 0) return Quickshell.iconPath(fallback)
        const cached = data._iconCache[cls]
        if (cached !== undefined) return cached

        let candidates = []
        const entry = DesktopEntries.heuristicLookup(cls)
        if (entry && entry.icon && entry.icon.length > 0)
            candidates.push(entry.icon)
        const lc = cls.toLowerCase()
        candidates.push(lc)
        // strip dotted prefix: "org.gnome.Nautilus" → "nautilus"
        const lastDot = lc.lastIndexOf(".")
        if (lastDot >= 0 && lastDot < lc.length - 1)
            candidates.push(lc.substring(lastDot + 1))
        // substitute underscores for hyphens (some themes prefer one or other)
        if (lc.indexOf("_") >= 0) candidates.push(lc.replace(/_/g, "-"))
        if (lc.indexOf("-") >= 0) candidates.push(lc.replace(/-/g, "_"))

        let result = ""
        let hit = false
        for (const c of candidates) {
            const p = Quickshell.iconPath(c, true)
            if (p && p.length > 0) { result = p; hit = true; break }
        }
        if (!hit) result = Quickshell.iconPath(fallback)
        // Only cache SUCCESSFUL theme lookups. If we fell through to the
        // fallback icon, don't cache — DesktopEntries.heuristicLookup may
        // not yet be populated (e.g. when the program was launched from a
        // terminal moments before the first overview open), and a later
        // call may succeed. This prevents "wrong icon for random apps on
        // first-launch-from-terminal" — subsequent resolves get a fresh
        // shot until they actually resolve to a real theme icon.
        if (hit) data._iconCache[cls] = result
        return result
    }

    function openSpecials() {
        let out = []
        for (const k in data.workspaces) {
            const w = data.workspaces[k]
            if (w.special) {
                const sn = data.specialName(w.name)
                if (sn.length > 0) out.push(sn)
            }
        }
        return out
    }

    //=========================================================================
    //  DISPATCH COMPATIBILITY  (Hyprland <0.55 hyprlang vs >=0.55 lua)
    //=========================================================================
    // Since Hyprland 0.55, hyprlang is deprecated in favour of lua, and
    // `hyprctl dispatch` is a shorthand for `hyprctl eval 'hl.dispatch(...)'`.
    // The legacy string form ("focuswindow address:0x123") is no longer
    // parsed — it gets spliced into lua source verbatim and blows up with:
    //     error: [string "return hl.dispatch(focuswindow address:0x...)"]:1:
    //            ')' expected near 'address'
    // Quickshell exposes Hyprland.usingLua so we can emit the right form for
    // whichever version is running. Every dispatch in this project goes
    // through the helpers below — never call Hyprland.dispatch() directly.
    //
    // Lua dispatcher equivalents (from the 0.55+ wiki):
    //   focuswindow address:X        -> hl.dsp.focus({ window = "address:X" })
    //   workspace N                  -> hl.dsp.focus({ workspace = N })
    //   togglespecialworkspace NAME  -> hl.dsp.workspace.toggle_special("NAME")
    //   movetoworkspacesilent N,addr -> hl.dsp.window.move({ workspace = N,
    //                                       window = "address:X", follow = false })
    //   closewindow address:X        -> hl.dsp.window.close({ window = "address:X" })
    // Quickshell's Hyprland.usingLua is documented as "false until the
    // Hyprland module is initialized", so binding it to a property at
    // singleton-construction time latches `false` forever and we keep
    // emitting legacy syntax. Read it FRESH on every dispatch instead —
    // dispatches only happen on user action, long after init.
    //
    // Config.luaDispatch overrides detection: "auto" (default) trusts
    // Hyprland.usingLua, "always"/"never" force one syntax. Use the override
    // if your Quickshell predates the usingLua property.
    function _isLua() {
        const mode = Config.luaDispatch
        if (mode === "always") return true
        if (mode === "never")  return false
        try {
            if (Hyprland.usingLua !== undefined) return !!Hyprland.usingLua
        } catch (e) {}
        // Fall back to sniffing for a lua config on disk: Hyprland 0.55+
        // reads ~/.config/hypr/hyprland.lua.
        return data._luaConfigPresent
    }

    // One-shot probe for ~/.config/hypr/hyprland.lua, used only when
    // Hyprland.usingLua is unavailable.
    property bool _luaConfigPresent: false
    property Process _luaProbe: Process {
        command: ["sh", "-c",
                  "test -f \"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua\" && echo yes || echo no"]
        stdout: StdioCollector {
            id: luaProbeOut
            onStreamFinished: data._luaConfigPresent =
                (luaProbeOut.text.indexOf("yes") >= 0)
        }
    }

    // Quote a lua string literal. Addresses and workspace names are tame
    // (hex digits / identifier-ish), but escape anyway so a workspace named
    // with a quote can't break out of the expression.
    function _luaStr(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
    }

    // A lua workspace value: numeric ids go through bare, names get quoted.
    function _luaWs(ws) {
        const n = parseInt(ws)
        if (!isNaN(n) && String(n) === String(ws)) return String(n)
        return data._luaStr(ws)
    }

    function dispatchFocusWindow(addr) {
        if (data._isLua())
            Hyprland.dispatch("hl.dsp.focus({ window = "
                              + data._luaStr("address:" + addr) + " })")
        else
            Hyprland.dispatch("focuswindow address:" + addr)
    }

    function dispatchCloseWindow(addr) {
        if (data._isLua())
            Hyprland.dispatch("hl.dsp.window.close({ window = "
                              + data._luaStr("address:" + addr) + " })")
        else
            Hyprland.dispatch("closewindow address:" + addr)
    }

    function dispatchWorkspace(ws) {
        if (data._isLua())
            Hyprland.dispatch("hl.dsp.focus({ workspace = "
                              + data._luaWs(ws) + " })")
        else
            Hyprland.dispatch("workspace " + ws)
    }

    // name == "" toggles the last-used special workspace.
    function dispatchToggleSpecial(name) {
        if (data._isLua()) {
            Hyprland.dispatch(name && name.length > 0
                ? ("hl.dsp.workspace.toggle_special(" + data._luaStr(name) + ")")
                : "hl.dsp.workspace.toggle_special()")
        } else {
            Hyprland.dispatch(name && name.length > 0
                ? ("togglespecialworkspace " + name)
                : "togglespecialworkspace")
        }
    }

    // Move a window to a workspace without following it (movetoworkspacesilent).
    // `ws` is either a numeric id or a name like "special:stash".
    function dispatchMoveWindowSilent(addr, ws) {
        if (data._isLua())
            Hyprland.dispatch("hl.dsp.window.move({ workspace = "
                              + data._luaWs(ws) + ", window = "
                              + data._luaStr("address:" + addr)
                              + ", follow = false })")
        else
            Hyprland.dispatch("movetoworkspacesilent " + ws + ",address:" + addr)
    }

    // A single `hyprctl --batch` argument that closes one window. Used by
    // AltTab's close-all. Returns the payload WITHOUT the leading "dispatch ".
    function batchCloseWindowArg(addr) {
        return data._isLua()
            ? ("dispatch hl.dsp.window.close({ window = "
               + data._luaStr("address:" + addr) + " })")
            : ("dispatch closewindow address:" + addr)
    }

    // Switch to a workspace, correctly dismissing any overlaid special first.
    function dispatchSwitch(id, name) {
        const fmId = data.focusedMonitorId
        let ms = data.monitorSpecial

        if (data.isSpecial(id, name)) {
            const sub = data.specialName(name)
            data.dispatchToggleSpecial(sub)
            const prev = ms[fmId] || ""
            let nms = Object.assign({}, ms)
            nms[fmId] = (prev === sub) ? "" : sub
            data.monitorSpecial = nms
            return
        }

        const fw = Hyprland.focusedWorkspace
        const focusedName = (fw && typeof fw.name === "string") ? fw.name : ""
        const liveSpecial = (fw && data.isSpecial(fw.id, focusedName))
                            ? data.specialName(focusedName) : ""
        const cachedSpecial = ms[fmId] || ""
        const visibleSpecial = liveSpecial.length > 0 ? liveSpecial : cachedSpecial
        if (visibleSpecial && visibleSpecial.length > 0) {
            data.dispatchToggleSpecial(visibleSpecial)
            let nms = Object.assign({}, ms)
            nms[fmId] = ""
            data.monitorSpecial = nms
        }
        data.dispatchWorkspace(id)
    }

    function createNewSpecial() {
        const taken = {}
        for (const k in data.workspaces) {
            if (data.workspaces[k].special)
                taken[data.specialName(data.workspaces[k].name)] = true
        }
        let base = Config.newSpecialPrefix
        let candidate = base
        let i = 2
        while (taken[candidate]) candidate = base + "-" + (i++)
        data.dispatchToggleSpecial(candidate)
        let nms = Object.assign({}, data.monitorSpecial)
        nms[data.focusedMonitorId] = candidate
        data.monitorSpecial = nms
    }

    //=========================================================================
    //  INTERNALS
    //=========================================================================
    property var _wsModels: ({})       // wsId(string) -> ListModel
    property var _addrToWs: ({})       // address -> wsId
    property bool _bootstrapped: false

    property Component _wsModelComponent: Component { ListModel {} }

    //--- BOOTSTRAP: single hyprctl pull at startup ---
    Component.onCompleted: {
        data._luaProbe.running = true
        data._bootstrap()
    }

    function _bootstrap() {
        try { if (Hyprland.refreshToplevels)  Hyprland.refreshToplevels()  } catch (e) {}
        try { if (Hyprland.refreshWorkspaces) Hyprland.refreshWorkspaces() } catch (e) {}
        try { if (Hyprland.refreshMonitors)   Hyprland.refreshMonitors()   } catch (e) {}
        _bootstrapProc.running = true
    }

    property Process _bootstrapProc: Process {
        command: ["sh", "-c",
                  "hyprctl clients -j; printf '__SPLIT__'; hyprctl monitors -j"]
        stdout: StdioCollector {
            id: bootstrapOut
            onStreamFinished: data._populateFromHyprctl(bootstrapOut.text, true)
        }
    }

    //--- ADDRESS NORMALIZATION ---
    // Hyprland event socket sends bare addresses (no "0x" prefix); hyprctl JSON
    // and Quickshell's lastIpcObject use "0x" prefixed addresses. Normalize to
    // the prefixed form everywhere we store/compare.
    function _normAddr(a) {
        if (typeof a !== "string" || a.length === 0) return ""
        if (a.substring(0, 2) === "0x") return a
        return "0x" + a
    }

    //--- WAYLAND HANDLE MAP ---
    function _rebuildHandleMap() {
        const tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        let m = {}
        for (const t of tls) {
            // A toplevel mid-teardown can still be in the collection with a
            // null/!valid wayland handle. Publishing one of those would let a
            // ScreencopyView bind a dead object, so skip anything that isn't
            // fully live.
            if (!t) continue
            const obj = t.lastIpcObject
            const addr = obj ? obj.address : null
            const wl = t.wayland
            if (!addr || !wl) continue
            m[addr] = wl
        }
        data.handleByAddr = m
    }

    // Synchronously remove one address's handle. Used on closewindow so the
    // preview Loader deactivates before the toplevel's wayland object dies.
    // Reassigns the map (new object reference) so dependent bindings — the
    // Loader's `active` and the ScreencopyView's `captureSource` — re-evaluate
    // immediately rather than on the next map rebuild.
    function _dropHandle(addr) {
        if (!addr) return
        if (data.handleByAddr[addr] === undefined) return
        let m = {}
        for (const k in data.handleByAddr) {
            if (k !== addr) m[k] = data.handleByAddr[k]
        }
        data.handleByAddr = m
    }

    property Connections _tlConn: Connections {
        target: Hyprland.toplevels
        ignoreUnknownSignals: true
        function onValuesChanged() {
            data._rebuildHandleMap()
            // Wayland just announced a toplevel change (open/close/handle
            // swap). That's a strong signal Hyprland has updated its internal
            // state, so trigger a sync immediately. Idempotent — if nothing
            // changed, the diff produces zero ListModel mutations.
            data._queueGeomSync()
        }
    }

    //--- ROW NORMALIZATION ---
    function _rowFromClient(c, mmap) {
        const mon = (mmap || data.monitorById)[c.monitor]
                  || (mmap || data.monitorById)[data.focusedMonitorId]
                  || { x: 0, y: 0, w: 1920, h: 1080 }
        const clamp = v => Math.max(0, Math.min(1, v))
        const addr = c.address || ""
        return {
            address:  addr,
            rx:       clamp((c.at[0]   - mon.x) / mon.w),
            ry:       clamp((c.at[1]   - mon.y) / mon.h),
            rw:       clamp( c.size[0]          / mon.w),
            rh:       clamp( c.size[1]          / mon.h),
            floating: !!c.floating,
            title:    c.title || "",
            cls:      c.class || c.initialClass || "",
            icon:     data.resolveIcon(c.class || c.initialClass || "",
                                       Config.fallbackIcon)
            // wl handle is NOT stored as a ListModel role. Qt's ListModel
            // refuses to reliably create a role for a QObject reference and
            // set()-ing one later can segfault. Instead, consumers look up
            // the wayland handle by address via HyprData.handleByAddr —
            // which is a `var` property that fires its change signal on
            // reassignment, so bindings that reference it stay reactive.
        }
    }

    //--- POPULATE FROM HYPRCTL (bootstrap + sync) ---
    function _populateFromHyprctl(text, isBootstrap) {
        const parts = text.split("__SPLIT__")
        let cs = [], mons = []
        try { cs   = JSON.parse(parts[0]) } catch (e) {}
        try { mons = JSON.parse(parts[1]) } catch (e) {}
        if (Config.skipUnmapped) cs = cs.filter(c => c.mapped !== false)
        cs = cs.filter(c => c.size && c.size[0] > 0 && c.size[1] > 0)

        // monitors
        let mmap = {}, mspecial = {}
        for (const m of mons) {
            mmap[m.id] = {
                id: m.id, name: m.name,
                x: m.x, y: m.y, w: m.width, h: m.height
            }
            const sw = m.specialWorkspace
            const sname = (sw && typeof sw.name === "string") ? sw.name : ""
            mspecial[m.id] = sname.length > 0
                             ? (data.specialName(sname) || sname) : ""
        }
        data.monitorById = mmap
        data.monitorSpecial = mspecial
        const fm = Hyprland.focusedMonitor
        data.focusedMonitorId = fm ? fm.id : (mons.length > 0 ? mons[0].id : 0)

        // Rebuild handle map BEFORE building rows — so _rowFromClient picks
        // up the freshest wl handle for each address. Without this ordering,
        // brand-new windows' rows would be appended with wl=null even when
        // the handle is already available from Hyprland.toplevels.
        data._rebuildHandleMap()

        // workspaces — ensure all referenced workspaces exist in our map
        let nws = Object.assign({}, data.workspaces)
        let touchedWs = false
        for (const c of cs) {
            const w = c.workspace || {}
            const wid = (w.id !== undefined) ? w.id : 0
            if (!nws[wid]) {
                nws[wid] = {
                    id: wid,
                    name: (w.name && w.name.length > 0) ? w.name : String(wid),
                    special: data.isSpecial(wid, w.name),
                    monId: c.monitor
                }
                touchedWs = true
            }
        }
        if (touchedWs || isBootstrap) {
            data.workspaces = nws
        }

        // address-keyed surgical sync against fresh client list.
        let freshByAddr = {}
        for (const c of cs) {
            const w = c.workspace || {}
            const wid = (w.id !== undefined) ? w.id : 0
            const row = data._rowFromClient(c, mmap)
            if (row.address) freshByAddr[row.address] = { wsid: wid, row: row }
        }

        // remove rows whose address is gone or has moved
        let newAddrToWs = {}
        for (const wsidStr in data._wsModels) {
            const lm = data._wsModels[wsidStr]
            const wsid = parseInt(wsidStr)
            for (let i = lm.count - 1; i >= 0; i--) {
                const row = lm.get(i)
                const addr = row.address
                const fresh = freshByAddr[addr]
                if (!fresh || fresh.wsid !== wsid) {
                    lm.remove(i)
                } else {
                    const f = fresh.row
                    // Detect changes that should trigger a set():
                    //   - geometry (rx/ry/rw/rh) — common after re-tile
                    //   - floating/title — minor updates
                    //   - icon — the initial resolveIcon() call for a
                    //     brand-new window (or one seen before
                    //     DesktopEntries populated) may return the generic
                    //     fallback URL. Once DesktopEntries has loaded and
                    //     resolveIcon returns a real theme icon on a later
                    //     sync, we `set()` the row so the tile updates.
                    if (row.rx !== f.rx || row.ry !== f.ry
                        || row.rw !== f.rw || row.rh !== f.rh
                        || row.floating !== f.floating
                        || row.title !== f.title
                        || row.icon !== f.icon) {
                        lm.set(i, f)
                    }
                    newAddrToWs[addr] = wsid
                }
            }
        }
        // append rows that exist in fresh but not yet in our model
        for (const addr in freshByAddr) {
            if (newAddrToWs[addr] !== undefined) continue
            const f = freshByAddr[addr]
            data.windowsFor(f.wsid).append(f.row)
            newAddrToWs[addr] = f.wsid
        }
        data._addrToWs = newAddrToWs

        if (isBootstrap || touchedWs) {
            data._bootstrapped = true
        } else {
            data._bootstrapped = true
        }
        data.updated()
    }

    //--- EVENT-DRIVEN MUTATIONS ---
    property Connections _evConn: Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(event) { data._handleEvent(event) }
    }

    function _handleEvent(event) {
        if (!data._bootstrapped) return
        const name = event.name
        const payload = event.data

        if (name === "openwindow") {
            // openwindow>>addr,wsname,class,title — no geometry, must refetch
            data._rebuildHandleMap()
            data._queueGeomSync()
            return
        }
        if (name === "closewindow") {
            const addr = data._normAddr(payload.trim())
            // ORDER MATTERS. Drop the wayland handle FIRST, synchronously.
            //
            // The Loader that owns each ScreencopyView is gated on
            // `!!HyprData.handleByAddr[address]`, so purging the address here
            // flips that binding false on this very tick and the
            // ScreencopyView is torn down while its capture target is still
            // a live wayland object.
            //
            // Removing the ListModel row first is NOT enough: the Repeater
            // destroys delegates asynchronously, so the ScreencopyView can
            // outlive the toplevel by a frame and issue a screencopy request
            // against a destroyed object. The compositor answers that by
            // killing the connection:
            //     The Wayland connection experienced a fatal error:
            //     Invalid argument
            // which takes the whole shell down.
            data._dropHandle(addr)
            data._removeWindowByAddr(addr)
            data.windowClosed(addr)
            return
        }
        if (name === "movewindowv2") {
            const parts = payload.split(",")
            const addr = data._normAddr(parts[0])
            const wsid = parseInt(parts[1])
            const wsname = parts.slice(2).join(",")
            if (!isNaN(wsid)) {
                const fromWs = data._moveWindowToWs(addr, wsid, wsname)
                if (fromWs !== null) data.windowMoved(addr, fromWs, wsid)
            }
            data._rebuildHandleMap()
            data._queueGeomSync()
            return
        }
        if (name === "movewindow") {
            const parts = payload.split(",")
            const addr = data._normAddr(parts[0])
            const wsname = parts.slice(1).join(",")
            let wsid = -999
            for (const k in data.workspaces) {
                if (data.workspaces[k].name === wsname) {
                    wsid = parseInt(k); break
                }
            }
            if (wsid !== -999) {
                const fromWs = data._moveWindowToWs(addr, wsid, wsname)
                if (fromWs !== null) data.windowMoved(addr, fromWs, wsid)
            }
            data._rebuildHandleMap()
            data._queueGeomSync()
            return
        }
        if (name === "windowtitlev2") {
            const idx = payload.indexOf(",")
            if (idx >= 0) {
                const addr = data._normAddr(payload.substring(0, idx))
                const title = payload.substring(idx + 1)
                data._setRow(addr, { title: title })
            }
            return
        }
        if (name === "windowtitle") {
            data._queueGeomSync()
            return
        }
        if (name === "activespecial" || name === "activespecialv2") {
            // v1: wsname,monname  (wsname empty when closing)
            // v2: wsid,wsname,monname
            const parts = payload.split(",")
            let wsname = "", monname = ""
            if (name === "activespecialv2") {
                wsname  = parts[1] || ""
                monname = parts[2] || ""
            } else {
                wsname  = parts[0] || ""
                monname = parts[1] || ""
            }
            let monId = -1
            for (const k in data.monitorById) {
                if (data.monitorById[k].name === monname) {
                    monId = parseInt(k); break
                }
            }
            if (monId >= 0) {
                let nms = Object.assign({}, data.monitorSpecial)
                nms[monId] = wsname.length > 0
                             ? (data.specialName(wsname) || wsname) : ""
                data.monitorSpecial = nms
            }
            return
        }
        if (name === "createworkspacev2") {
            const parts = payload.split(",")
            const wid = parseInt(parts[0])
            const wname = parts.slice(1).join(",")
            if (!isNaN(wid) && !data.workspaces[wid]) {
                let nws = Object.assign({}, data.workspaces)
                nws[wid] = {
                    id: wid, name: wname,
                    special: data.isSpecial(wid, wname),
                    monId: data.focusedMonitorId
                }
                data.workspaces = nws
            }
            return
        }
        if (name === "createworkspace") {
            data._queueGeomSync()
            return
        }
        if (name === "destroyworkspacev2") {
            const parts = payload.split(",")
            const wid = parseInt(parts[0])
            if (!isNaN(wid) && data.workspaces[wid]) {
                let nws = Object.assign({}, data.workspaces)
                delete nws[wid]
                data.workspaces = nws
                if (data._wsModels[wid.toString()])
                    data._wsModels[wid.toString()].clear()
            }
            return
        }
        if (name === "destroyworkspace") {
            data._queueGeomSync()
            return
        }
        if (name === "fullscreen"
            || name === "changefloatingmode"
            || name === "monitoraddedv2"
            || name === "monitorremovedv2"
            || name === "configreloaded") {
            data._queueGeomSync()
            return
        }
    }

    //--- DIRECT MUTATIONS (called by event handlers) ---
    function _removeWindowByAddr(addr) {
        const wsid = data._addrToWs[addr]
        if (wsid === undefined) return
        const lm = data._wsModels[wsid.toString()]
        if (lm) {
            for (let i = 0; i < lm.count; i++) {
                if (lm.get(i).address === addr) { lm.remove(i); break }
            }
        }
        let m = Object.assign({}, data._addrToWs)
        delete m[addr]
        data._addrToWs = m
    }

    function _setRow(addr, patch) {
        const wsid = data._addrToWs[addr]
        if (wsid === undefined) return
        const lm = data._wsModels[wsid.toString()]
        if (!lm) return
        for (let i = 0; i < lm.count; i++) {
            if (lm.get(i).address === addr) { lm.set(i, patch); break }
        }
    }

    // Returns the fromWs id, or null if we didn't have the row locally.
    function _moveWindowToWs(addr, wsid, wsname) {
        if (!data.workspaces[wsid]) {
            let nws = Object.assign({}, data.workspaces)
            nws[wsid] = {
                id: wsid, name: wsname,
                special: data.isSpecial(wsid, wsname),
                monId: data.focusedMonitorId
            }
            data.workspaces = nws
        }
        const oldWsid = data._addrToWs[addr]
        let row = null
        if (oldWsid !== undefined) {
            const oldLm = data._wsModels[oldWsid.toString()]
            if (oldLm) {
                for (let i = 0; i < oldLm.count; i++) {
                    if (oldLm.get(i).address === addr) {
                        const r = oldLm.get(i)
                        row = {
                            address: r.address,
                            rx: r.rx, ry: r.ry, rw: r.rw, rh: r.rh,
                            floating: r.floating,
                            title: r.title,
                            cls: r.cls,
                            icon: r.icon
                        }
                        oldLm.remove(i)
                        break
                    }
                }
            }
        }
        if (row) data.windowsFor(wsid).append(row)
        let m = Object.assign({}, data._addrToWs)
        m[addr] = wsid
        data._addrToWs = m
        return oldWsid !== undefined ? oldWsid : null
    }

    //--- HYPRCTL GEOMETRY SYNC ---
    //
    // We need fresh geometry after layout-changing events (openwindow,
    // movewindow, fullscreen, configreload, monitor add/remove). Hyprland's
    // event socket fires immediately, but `hyprctl clients -j` may still
    // return stale state for ~10–300ms while Hyprland finishes processing
    // its own dispatch. So we don't trust one sync — we run a short BURST.
    //
    // The burst: schedule a sync now (~30ms debounce so events that arrive
    // back-to-back coalesce into one), then schedule another at 120ms, then
    // 350ms. Each sync's diff is idempotent: rows that haven't changed since
    // last sync produce zero ListModel mutations. Spurious syncs cost ~1
    // hyprctl fork; the gain is robustness against arbitrary Hyprland lag.
    property Timer _syncT1: Timer { interval:  30; repeat: false; onTriggered: data._kickSync() }
    property Timer _syncT2: Timer { interval: 120; repeat: false; onTriggered: data._kickSync() }
    property Timer _syncT3: Timer { interval: 350; repeat: false; onTriggered: data._kickSync() }

    function _queueGeomSync() {
        // ask Quickshell to refresh its internal Hyprland views — that
        // populates HyprlandToplevel.lastIpcObject for newly-opened windows,
        // which is what _rebuildHandleMap reads. Without this, brand-new
        // windows may show as gray boxes until something else triggers a
        // refresh.
        try { if (Hyprland.refreshToplevels)  Hyprland.refreshToplevels()  } catch (e) {}
        try { if (Hyprland.refreshWorkspaces) Hyprland.refreshWorkspaces() } catch (e) {}
        data._syncT1.restart()
        data._syncT2.restart()
        data._syncT3.restart()
    }

    // Kick a fresh sync. If a previous sync's process is still running, we
    // let it finish (its result is also valid — the diff handles either
    // arriving in any order) and start a new run. Quickshell's Process
    // re-runs cleanly if `running` is toggled.
    function _kickSync() {
        if (data._syncProc.running) {
            // already running — set false then true to force a re-spawn
            // after the current invocation finishes
            data._syncProc.running = false
        }
        data._syncProc.running = true
    }

    property Process _syncProc: Process {
        command: ["sh", "-c",
                  "hyprctl clients -j; printf '__SPLIT__'; hyprctl monitors -j"]
        stdout: StdioCollector {
            id: syncOut
            onStreamFinished: data._populateFromHyprctl(syncOut.text, false)
        }
    }
}
