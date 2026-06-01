import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// One workspace tile: mini-desktop with window wireframes/live previews
// and a workspace number badge. Pure content — selection rings are drawn
// by a single floating SelectionIndicator in the parent view, so it can
// animate smoothly across the grid instead of changing per-tile state.
//
// Inputs: wsId, wsName, special, windows[], monW, monH, showBadge
// Signals:
//   tileClicked()
//   windowClicked(address)
//   windowMiddleClicked(address)
Item {
    id: tile

    // --- inputs ---
    property int    wsId: 0
    property string wsName: ""
    property bool   special: false
    property var    windows: []
    property real   monW: 16
    property real   monH: 9
    property bool   showBadge: true
    property bool   isEmpty: windows.length === 0

    signal tileClicked()
    signal windowClicked(string address)
    signal windowMiddleClicked(string address)

    readonly property real innerW: Config.previewWidth - Config.previewInset * 2
    readonly property real innerH:
        Math.max(60, innerW * (monH / Math.max(1, monW)))

    implicitWidth: Config.previewWidth
    implicitHeight: innerH + Config.previewInset * 2

    Rectangle {
        id: tileBg
        anchors.fill: parent
        radius: Config.tileRadius
        color: Config.tileBackground
        // Default resting border; the floating SelectionIndicator overlays the
        // selected tile's ring on top of this.
        border.width: Config.borderWidth
        border.color: hover.hovered ? Config.hoverOutline : Config.panelBorder
        Behavior on border.color { ColorAnimation { duration: 90 } }
    }

    // mini-desktop area
    Item {
        id: screen
        x: Config.previewInset
        y: Config.previewInset
        width: tile.innerW
        height: tile.innerH
        clip: true

        Repeater {
            model: tile.windows
            delegate: Rectangle {
                required property var modelData
                x: modelData.rx * screen.width
                y: modelData.ry * screen.height
                width:  Math.max(6, modelData.rw * screen.width)
                height: Math.max(6, modelData.rh * screen.height)
                radius: 3
                color: Config.windowFill
                border.width: 1
                border.color: Config.windowBorder
                clip: true

                // fallback icon
                Image {
                    anchors.centerIn: parent
                    visible: Config.showWindowIcons
                    opacity: Config.windowIconOpacity
                    readonly property real s:
                        Math.min(parent.width, parent.height) * 0.55
                    width:  Math.max(8, Math.min(Config.windowIconMax, s))
                    height: width
                    source: modelData.icon
                    sourceSize.width: width
                    sourceSize.height: width
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }

                // live screencopy preview
                Loader {
                    anchors.fill: parent
                    active: Config.livePreviews && !!modelData.wl
                    sourceComponent: ScreencopyView {
                        anchors.fill: parent
                        live: Config.liveCapture
                        captureSource: modelData.wl
                        opacity: hasContent ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }

                // window-level click target (used by overview for focus/close)
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.MiddleButton)
                            tile.windowMiddleClicked(modelData.address)
                        else
                            tile.windowClicked(modelData.address)
                    }
                }
            }
        }

        // empty-workspace hint
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
    }

    // corner badge (workspace number / name)
    Rectangle {
        visible: tile.showBadge
        x: Config.previewInset + 4
        y: Config.previewInset + 4
        width: wsLabel.implicitWidth + 12
        height: wsLabel.implicitHeight + 5
        radius: 7
        // alpha-in-color so the label doesn't get washed out by opacity cascade
        color: Qt.rgba(Config.backgroundColor.r,
                       Config.backgroundColor.g,
                       Config.backgroundColor.b,
                       0.78)
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

    // whole-tile click (background area not covered by a window box)
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        // window-level MouseAreas above will consume their hits first
        onClicked: tile.tileClicked()
        z: -1
    }
}
