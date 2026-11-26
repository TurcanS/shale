import QtQuick
import "../core"

// The 2 px keyboard focus ring, for controls that aren't Buttons (Button draws its own). Fills its parent, grown
// by `inset` on every side; the parent sets `visible` from its control's visualFocus.
Rectangle {
    property real inset: 0
    anchors.fill: parent
    anchors.margins: -inset
    z: 10
    radius: Math.min(width, height) / 2
    color: "transparent"
    border.width: 2
    border.color: Theme.text
    opacity: 0.85
}
