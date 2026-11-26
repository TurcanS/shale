import QtQuick
import "../core"

// What makes a key sit up off its surface: a faint dark lip a pixel below it and a fainter light line along its top
// edge. Put it inside the key's background Rectangle. "On" keys get the full lip; keys at rest (resting) a lighter
// one. While the key is pressed down (sunk 0–1) the lip goes, as if the key met the panel.
Rectangle {
    id: lip
    property bool shown: true
    property bool resting: false
    property real sunk: 0
    anchors.fill: parent
    anchors.topMargin: 1
    anchors.bottomMargin: -1
    // Negative z draws under the parent, so only the edge below the key shows.
    z: -1
    radius: parent ? parent.radius : 0
    color: resting ? Theme.restLip : Theme.raisedLip
    opacity: (shown ? 1 : 0) * (1 - Math.min(1, sunk))
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    // The top light line lives on the key itself (above its fill), kept short of the rounded corners.
    Rectangle {
        parent: lip.parent
        x: lip.radius * 0.7
        y: 0
        width: (parent ? parent.width : 0) - 2 * x
        height: 1
        color: lip.resting ? Theme.restSheen : Theme.raisedSheen
        opacity: lip.opacity
        visible: lip.visible && width > 4
    }
}
