import QtQuick
import "../core"
import "../components" as C

// One part of the status key: its own click, scroll and hint, with a wash on hover.
BarKey {
    id: part
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    leftPadding: 6
    rightPadding: 6
    cornerRadius: Theme.radiusSegment
    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            radius: Theme.radiusSegment
            color: part.selected ? Theme.keySelected : part.hovered || part.down || part.visualFocus ? part.wash : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
            C.Raise {
                shown: part.selected
            }
        }
    }
}
