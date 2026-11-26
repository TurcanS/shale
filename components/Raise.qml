import QtQuick
import "../core"

// The lip under a raised "on" key: put it inside the key's background Rectangle and bind `shown` to the on state.
// It sits a pixel lower than the key and below it (negative z draws under the parent), so only its bottom edge
// shows, like the chosen option of a Segmented.
Rectangle {
    property bool shown: true
    anchors.fill: parent
    anchors.topMargin: 1
    anchors.bottomMargin: -1
    z: -1
    radius: parent.radius
    color: Theme.raisedLip
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
}
