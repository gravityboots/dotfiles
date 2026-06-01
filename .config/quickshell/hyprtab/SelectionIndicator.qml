import QtQuick

// A floating selection ring + tint wash that smoothly animates between
// workspace tiles.
//
// IMPORTANT: This component must NOT be placed as a child of a Grid/Row/Column
// (anything that auto-lays out its children) — otherwise the layout container
// will treat the indicator as a cell of its own and reserve a slot for it past
// the last tile, which produces phantom rows and bogus animation endpoints.
//
// Use it inside a plain `Item` that overlays the grid. Anchor that overlay
// `anchors.fill: theGrid` so the indicator's coordinate space matches the
// grid's, then it can read raw `target.x`/`target.y`.
Item {
    id: ind

    // The tile being indicated. The view sets this via moveTo().
    property Item target: null
    property bool special: false
    property bool shown:   false

    // Resolved geometry of the current target, refreshed via _track() so we're
    // not vulnerable to a half-destroyed delegate or transient (0,0) frame.
    property real targetX:      0
    property real targetY:      0
    property real targetWidth:  0
    property real targetHeight: 0

    property int moveDuration: 220
    property int fadeDuration: 140

    visible: shown && target !== null
    opacity: (shown && target !== null && targetWidth > 0) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: ind.fadeDuration } }

    x:      targetX
    y:      targetY
    width:  targetWidth
    height: targetHeight

    Behavior on x      { NumberAnimation { duration: ind.moveDuration; easing.type: Easing.OutCubic } }
    Behavior on y      { NumberAnimation { duration: ind.moveDuration; easing.type: Easing.OutCubic } }
    Behavior on width  { NumberAnimation { duration: ind.moveDuration; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: ind.moveDuration; easing.type: Easing.OutCubic } }

    // ring
    Rectangle {
        anchors.fill: parent
        radius: Config.tileRadius
        color: "transparent"
        border.width: Config.selectedBorderWidth
        border.color: ind.special ? Config.specialAccent : Config.selectedOutline
        Behavior on border.color { ColorAnimation { duration: ind.fadeDuration } }
    }

    // faint inner tint
    Rectangle {
        anchors.fill: parent
        anchors.margins: Config.previewInset
        radius: Config.tileRadius - 2
        color: ind.special ? Config.specialAccent : Config.selectedBackground
        opacity: Config.selectedTint
    }

    // Whenever the target item moves or resizes (e.g. workspace list rebuilt,
    // window moved triggering tile content reflow), pull the new numbers.
    Connections {
        target: ind.target
        ignoreUnknownSignals: true
        function onXChanged()      { ind._track() }
        function onYChanged()      { ind._track() }
        function onWidthChanged()  { ind._track() }
        function onHeightChanged() { ind._track() }
    }

    function _track() {
        if (!ind.target) return
        // Guard against transient zero-size frames during layout passes.
        if (ind.target.width <= 0 || ind.target.height <= 0) return
        ind.targetX      = ind.target.x
        ind.targetY      = ind.target.y
        ind.targetWidth  = ind.target.width
        ind.targetHeight = ind.target.height
    }

    function moveTo(t, isSpecial) {
        // If the new target is in a valid layout state, capture its geometry
        // immediately. Otherwise wait until it lays out and let the Connections
        // pick it up.
        ind.target  = t
        ind.special = !!isSpecial
        if (t && t.width > 0 && t.height > 0) {
            ind.targetX = t.x; ind.targetY = t.y
            ind.targetWidth = t.width; ind.targetHeight = t.height
        }
        ind.shown = true
    }
    function hide() { ind.shown = false }
}
