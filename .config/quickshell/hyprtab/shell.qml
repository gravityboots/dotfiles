//=============================================================================
//  hyprtab — Quickshell module with two views:
//   - AltTab:    Alt+Tab MRU workspace switcher (release-to-commit)
//   - Overview:  Super+Tab full overview with sequential workspaces, special
//                strip, and a "+" tile to spawn new special workspaces
//
//  Run with:    qs -c hyprtab
//  Lives at:    ~/.config/quickshell/hyprtab/
//
//  Files:
//    Config.qml         singleton — all knobs (colors, sizes, behavior)
//    HyprData.qml       singleton — shared client/monitor data + helpers
//    WorkspaceTile.qml  shared mini-desktop tile component
//    AltTab.qml         alt-tab switcher view
//    Overview.qml       overview view (Super+Tab + IPC)
//=============================================================================

import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Used by views to pick the right Quickshell.screens entry for the
    // currently-focused Hyprland monitor.
    function focusedScreen() {
        const mon = Hyprland.focusedMonitor
        if (mon)
            for (let i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === mon.name)
                    return Quickshell.screens[i]
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    AltTab   { id: altTab }
    Overview { id: overview }
}
