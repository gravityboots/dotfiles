pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// One source of truth for window/workspace state. Both AltTab and Overview ask
// for a refresh and read the same fields. Avoids duplicate `hyprctl` calls.
QtObject {
    id: data

    //=========================================================================
    //  PUBLIC STATE  (read-only for consumers; set internally by populate())
    //=========================================================================
    property var clients:   []   // raw `hyprctl clients -j` array (filtered)
    property var monitors:  []   // raw `hyprctl monitors -j`
    property var byWs:      ({}) // workspace id -> [{rx,ry,rw,rh,icon,wl,address,floating,title,cls}]
    property var wsMeta:    ({}) // workspace id -> {monId, name, special}
    property int focusedMonitorId: 0
    property var monitorById: ({}) // monId -> {x,y,w,h}
    // Per-monitor currently-visible special workspace (name without "special:" prefix).
    // monId -> name, or "" if no special is currently overlaid on that monitor.
    property var monitorSpecial: ({})

    signal updated()

    //=========================================================================
    //  TRIGGER A REFRESH  (call this when opening a view)
    //=========================================================================
    function refresh() {
        // best-effort toplevel cache refresh; helps fresh exec-once cold starts
        try { if (Hyprland.refreshToplevels) Hyprland.refreshToplevels(); } catch (e) {}
        try { if (Hyprland.refreshWorkspaces) Hyprland.refreshWorkspaces(); } catch (e) {}
        try { if (Hyprland.refreshMonitors)   Hyprland.refreshMonitors();   } catch (e) {}
        dataProc.running = true
    }

    property Process _proc: Process {
        id: dataProc
        command: ["sh", "-c",
                  "hyprctl clients -j; printf '__SPLIT__'; hyprctl monitors -j"]
        stdout: StdioCollector {
            id: dataOut
            onStreamFinished: data._populate(dataOut.text)
        }
    }

    //=========================================================================
    //  HELPERS
    //=========================================================================
    function isSpecial(id, name) {
        if (id !== undefined && id !== null && id < 0) return true
        return (typeof name === "string") && name.indexOf("special") === 0
    }

    // strip "special:" prefix from a workspace name; returns "" for an unnamed special
    function specialName(fullName) {
        if (typeof fullName !== "string") return ""
        const idx = fullName.indexOf(":")
        return idx >= 0 ? fullName.substring(idx + 1) : ""
    }

    function resolveIcon(cls, fallback) {
        if (!cls || cls.length === 0) return Quickshell.iconPath(fallback)
        const entry = DesktopEntries.heuristicLookup(cls)
        if (entry && entry.icon && entry.icon.length > 0)
            return Quickshell.iconPath(entry.icon, fallback)
        return Quickshell.iconPath(cls.toLowerCase(), fallback)
    }

    //=========================================================================
    //  INTERNAL: parse hyprctl output, build normalized lookup tables
    //=========================================================================
    function _populate(text) {
        const parts = text.split("__SPLIT__")
        let cs = [], mons = []
        try { cs   = JSON.parse(parts[0]); } catch (e) { cs   = [] }
        try { mons = JSON.parse(parts[1]); } catch (e) { mons = [] }

        if (Config.skipUnmapped) cs = cs.filter(c => c.mapped !== false)
        cs = cs.filter(c => c.size && c.size[0] > 0 && c.size[1] > 0)

        let mmap = {}
        let mspecial = {}
        for (const m of mons) {
            mmap[m.id] = { x: m.x, y: m.y, w: m.width, h: m.height }
            // hyprctl monitors reports the visible special workspace name with
            // its "special:" prefix, or "" when none is overlaid.
            const sw = m.specialWorkspace
            const sname = (sw && typeof sw.name === "string") ? sw.name : ""
            mspecial[m.id] = sname.length > 0 ? data.specialName(sname) || sname : ""
        }

        const fm = Hyprland.focusedMonitor
        const fmId = fm ? fm.id : (mons.length > 0 ? mons[0].id : 0)

        function norm(c) {
            const mon = mmap[c.monitor] || mmap[fmId] || { x: 0, y: 0, w: 1920, h: 1080 }
            const clamp = v => Math.max(0, Math.min(1, v))
            return {
                rx: clamp((c.at[0]   - mon.x) / mon.w),
                ry: clamp((c.at[1]   - mon.y) / mon.h),
                rw: clamp( c.size[0]          / mon.w),
                rh: clamp( c.size[1]          / mon.h)
            }
        }

        // address -> wayland capture handle, for ScreencopyView
        let handleByAddr = {}
        const tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (const t of tls) {
            const obj = t.lastIpcObject
            const addr = obj ? obj.address : null
            if (addr && t.wayland) handleByAddr[addr] = t.wayland
        }

        let byWs = {}, wsMeta = {}
        for (const c of cs) {
            const w = c.workspace || {}
            const wid = (w.id !== undefined) ? w.id : 0
            if (!byWs[wid]) {
                byWs[wid] = []
                wsMeta[wid] = {
                    monId:   c.monitor,
                    name:    (w.name && w.name.length > 0) ? w.name : String(wid),
                    special: data.isSpecial(wid, w.name)
                }
            }
            const r = norm(c)
            byWs[wid].push({
                rx: r.rx, ry: r.ry, rw: r.rw, rh: r.rh,
                floating: !!c.floating,
                address: c.address,
                title: c.title || "",
                cls: c.class || c.initialClass || "",
                icon: data.resolveIcon(c.class || c.initialClass || "", Config.fallbackIcon),
                wl: handleByAddr[c.address] || null
            })
        }

        data.monitors = mons
        data.clients = cs
        data.byWs = byWs
        data.wsMeta = wsMeta
        data.monitorById = mmap
        data.monitorSpecial = mspecial
        data.focusedMonitorId = fmId
        data.updated()
    }

    // pull list of currently open special workspace names (without "special:" prefix)
    function openSpecials() {
        let out = []
        for (const k in data.wsMeta) {
            const m = data.wsMeta[k]
            if (m.special) {
                const sn = data.specialName(m.name)
                if (sn.length > 0) out.push(sn)
            }
        }
        return out
    }

    // dispatch to switch to a workspace (handles special: prefix correctly).
    //
    // For a NORMAL target: first dismiss any special workspace currently overlaid
    // on the focused monitor, then switch. Hyprland renders the special *over*
    // the normal workspace, so switching the underlying normal workspace without
    // toggling the special off leaves the special hovering on top.
    //
    // For a SPECIAL target: toggle it.
    //
    // The local `monitorSpecial` model is updated optimistically on every
    // dispatch so consecutive switches inside one overview session see a
    // consistent view of "what's overlaid right now" without having to wait
    // for the async `hyprctl monitors -j` refresh to complete.
    function dispatchSwitch(id, name) {
        const fmId = data.focusedMonitorId
        let ms = data.monitorSpecial

        if (data.isSpecial(id, name)) {
            const sub = data.specialName(name)
            Hyprland.dispatch(sub.length > 0 ? ("togglespecialworkspace " + sub)
                                             : "togglespecialworkspace")
            // optimistic: this special is now the one overlaid on fmId, unless
            // we just toggled the same name off.
            const prev = ms[fmId] || ""
            ms[fmId] = (prev === sub) ? "" : sub
            data.monitorSpecial = ms
            return
        }

        // Normal workspace: close any open special on the focused monitor first.
        const visibleSpecial = ms[fmId]
        if (visibleSpecial && visibleSpecial.length > 0) {
            Hyprland.dispatch("togglespecialworkspace " + visibleSpecial)
            ms[fmId] = ""
            data.monitorSpecial = ms
        }
        Hyprland.dispatch("workspace " + id)
    }

    // create a new special workspace with auto-numbered name. Mirrors upstream:
    // "stash" -> "stash-2" -> "stash-3" ...
    function createNewSpecial() {
        const taken = {}
        for (const k in data.wsMeta) {
            if (data.wsMeta[k].special) taken[data.specialName(data.wsMeta[k].name)] = true
        }
        let base = Config.newSpecialPrefix
        let candidate = base
        let i = 2
        while (taken[candidate]) candidate = base + "-" + (i++)
        Hyprland.dispatch("togglespecialworkspace " + candidate)
        // optimistic update so any immediate follow-up dispatch sees the new
        // special as overlaid
        let ms = data.monitorSpecial
        ms[data.focusedMonitorId] = candidate
        data.monitorSpecial = ms
    }
}
