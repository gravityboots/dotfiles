import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// A miniature desktop tile: workspace number + scaled window boxes inside.
//
// Reads a ListModel of windows directly (from HyprData.windowsFor(wsId)). The
// ListModel is mutated in place by HyprData on Hyprland events — appending
// a row creates exactly one new delegate; removing a row destroys exactly
// one delegate; setting a row updates only the changed properties on the
// existing delegate. The ScreencopyView's `captureSource` reads `model.wl`
// directly from the ListModel row — populated and refreshed by HyprData on
// every sync, so newly-opened windows light up the moment their wayland
// handle becomes available.
Item {
    id: tile

    // --- inputs ---
    property int    wsId: 0
    property string wsName: ""
    property bool   special: false
    property var    windowsModel: null   // a ListModel from HyprData.windowsFor(wsId)
    property real   monW: 16
    property real   monH: 9
    property bool   showBadge: true
    property bool   dropHighlight: false
    // The currently-being-dragged window address (if any). The window with
    // this address renders invisibly so the user sees their drag take effect
    // immediately. The delegate stays alive (so its MouseArea continues
    // driving the drag).
    property string draggingAddress: ""
    // Whether to show a per-window hover wash. Off in alt-tab (the whole
    // workspace is the unit there); on in overview.
    property bool   windowHoverHighlight: true
    // Master gate for live screencopy. When false, all ScreencopyView Loaders
    // unload — no streaming, no GPU/memory cost. Bound by the parent view to
    // its visibility so previews only stream while the menu is on screen.
    property bool   previewsActive: true

    readonly property bool isEmpty: !windowsModel || windowsModel.count === 0

    signal tileClicked()
    signal windowClicked(string address)
    signal windowMiddleClicked(string address)
    signal windowDragStarted(var payload)
    signal windowDragMoved(real globalX, real globalY)
    signal windowDragEnded(real globalX, real globalY)
    // Emitted when the cursor enters/leaves a specific window thumbnail. The
    // overview uses this to drive a floating tooltip showing the window title.
    // `globalX/globalY` is the top-left of the hovered window box, in global
    // (screen) coordinates; `winWidth/winHeight` is its size.
    signal windowHoverEntered(string title, real globalX, real globalY,
                              real winWidth, real winHeight)
    signal windowHoverExited(string title)

    readonly property real innerW: Config.previewWidth - Config.previewInset * 2
    readonly property real innerH:
        Math.max(60, innerW * (monH / Math.max(1, monW)))

    implicitWidth:  Config.previewWidth
    implicitHeight: innerH + Config.previewInset * 2

    // --- background frame ---
    Rectangle {
        id: tileBg
        anchors.fill: parent
        radius: Config.tileRadius
        color: Config.tileBackground
        border.width: tile.dropHighlight ? Config.selectedBorderWidth
                                         : Config.borderWidth
        border.color: tile.dropHighlight ? Config.specialAccent
                      : (hover.hovered ? Config.hoverOutline : Config.panelBorder)
        Behavior on border.color { ColorAnimation { duration: 90 } }
    }

    // Tile-level click handling.
    //
    // Child MouseAreas (per-window winArea inside the screen Item below) are
    // declared AFTER this hover area, so they're stacked above and receive
    // mouse events first. The hover area's onClicked only fires if no child
    // accepted the click — i.e. when the user clicked on tile background or
    // on an empty tile. Either way, that's a workspace-switch click.
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: tile.tileClicked()
    }

    // --- inner mini-desktop ---
    Item {
        id: screen
        anchors.fill: parent
        anchors.margins: Config.previewInset
        clip: true

        Text {
            anchors.centerIn: parent
            visible: tile.isEmpty
            text: tile.special ? "Empty Special" : "Empty"
            color: Config.textColor
            opacity: 0.4
            font.pixelSize: Config.labelPixelSize
            font.family: Config.fontFamily.length > 0
                         ? Config.fontFamily : Qt.application.font.family
        }

        Repeater {
            id: winRepeater
            model: tile.windowsModel
            delegate: Item {
                id: winBox
                // ListModel roles in scope:
                //   address, rx, ry, rw, rh, floating, title, cls, icon
                readonly property bool suppressed:
                    tile.draggingAddress === model.address

                visible: model.rw > 0 && model.rh > 0

                x:      model.rx * screen.width
                y:      model.ry * screen.height
                width:  Math.max(6, model.rw * screen.width)
                height: Math.max(6, model.rh * screen.height)

                // Smooth geometry transitions when Hyprland re-tiles. Disabled
                // during user drag so the source frame doesn't visibly travel
                // toward (0,0) when temporarily hidden.
                Behavior on x      { enabled: !winArea.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on y      { enabled: !winArea.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on width  { enabled: !winArea.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: !winArea.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                // visible window thumbnail. We hide the rectangle (not the
                // outer Item) so the MouseArea keeps receiving events even
                // mid-drag.
                Rectangle {
                    id: winRect
                    anchors.fill: parent
                    visible: !winBox.suppressed
                    radius: 3
                    color: Config.windowFill
                    border.width: 1
                    border.color: Config.windowBorder
                    clip: true

                    // live preview via wayland screencopy. The handle is stored
                    // in the ListModel row's `wl` role, populated by HyprData's
                    // geometry sync. Binding to `model.wl` directly means the
                    // Loader reactivates the moment the row's wl handle is
                    // updated via lm.set() — no map-binding lag, no gray box
                    // hanging around after open.
                    Loader {
                        anchors.fill: parent
                        active: tile.previewsActive && Config.livePreviews && !!model.wl
                        sourceComponent: ScreencopyView {
                            anchors.fill: parent
                            live: true
                            captureSource: model.wl || null
                            opacity: hasContent ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                    }

                    // window icon — rendered on top of the preview as a small
                    // corner badge. Visible regardless of preview state so the
                    // user can still identify the window. The Loader-based
                    // preview is below in the z-stack, so this badge always
                    // wins paint order.
                    //
                    // sourceSize uses a fixed standard size (32) rather than
                    // binding to width — that way (a) the underlying image is
                    // decoded once and reused as the on-screen size animates,
                    // and (b) we request a size that actually exists in most
                    // icon themes (themes ship 16/22/24/32/48/64 — not 13).
                    // Without this, Qt's icon engine emits "Could not load
                    // icon" warnings at odd sizes like 13x13.
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
                        source: model.icon || ""
                        sourceSize.width: 32
                        sourceSize.height: 32
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        cache: true
                    }

                    // per-window hover wash (overview only)
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Config.selectedBackground
                        visible: tile.windowHoverHighlight
                        opacity: (tile.windowHoverHighlight && winArea.containsMouse)
                                 ? Config.selectedTint : 0
                        Behavior on opacity { NumberAnimation { duration: 90 } }
                    }
                }

                MouseArea {
                    id: winArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    hoverEnabled: true

                    property bool dragging: false
                    readonly property real dragThreshold: 6
                    property real pressX: 0
                    property real pressY: 0

                    onContainsMouseChanged: {
                        if (winArea.containsMouse && !winArea.dragging) {
                            const tl = winArea.mapToGlobal(0, 0)
                            tile.windowHoverEntered(
                                model.title || "",
                                tl.x, tl.y,
                                winBox.width, winBox.height)
                        } else {
                            tile.windowHoverExited(model.title || "")
                        }
                    }

                    onPressed: function(mouse) {
                        winArea.dragging = false
                        winArea.pressX = mouse.x
                        winArea.pressY = mouse.y
                    }
                    onPositionChanged: function(mouse) {
                        if (!(mouse.buttons & Qt.LeftButton)) return
                        if (!winArea.dragging) {
                            const dx = mouse.x - winArea.pressX
                            const dy = mouse.y - winArea.pressY
                            if (dx*dx + dy*dy >=
                                winArea.dragThreshold * winArea.dragThreshold) {
                                winArea.dragging = true
                                const tl  = winArea.mapToGlobal(0, 0)
                                const cur = winArea.mapToGlobal(mouse.x, mouse.y)
                                tile.windowDragStarted({
                                    address: model.address,
                                    icon:    model.icon,
                                    title:   model.title,
                                    wl:      model.wl || null,
                                    w:       winBox.width,
                                    h:       winBox.height,
                                    grabDX:  cur.x - tl.x,
                                    grabDY:  cur.y - tl.y
                                })
                            }
                        }
                        if (winArea.dragging) {
                            const g = winArea.mapToGlobal(mouse.x, mouse.y)
                            tile.windowDragMoved(g.x, g.y)
                        }
                    }
                    onReleased: function(mouse) {
                        if (mouse.button === Qt.MiddleButton) {
                            tile.windowMiddleClicked(model.address)
                            return
                        }
                        if (winArea.dragging) {
                            const g = winArea.mapToGlobal(mouse.x, mouse.y)
                            tile.windowDragEnded(g.x, g.y)
                            winArea.dragging = false
                            return
                        }
                        tile.windowClicked(model.address)
                    }
                }
            }
        }
    }

    // --- workspace number badge ---
    Rectangle {
        visible: tile.showBadge
        x: Config.previewInset + 4
        y: Config.previewInset + 4
        width:  wsLabel.implicitWidth  + 12
        height: wsLabel.implicitHeight + 5
        radius: 7
        color: Config.tileBadgeBg
        Text {
            id: wsLabel
            anchors.centerIn: parent
            text: tile.special ? ("\u2605 " + tile.wsName) : tile.wsName
            color: Config.textColor
            font.pixelSize: Config.labelPixelSize
            font.family: Config.fontFamily.length > 0
                         ? Config.fontFamily : Qt.application.font.family
        }
    }
}
