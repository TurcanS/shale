import QtQuick
import "../core"
import "../components" as C

// A 28 px key inside modules (Scan, Forget, +5 min).
C.Button {
    id: smallKey
    property color rest: Theme.key
    implicitHeight: 28
    leftPadding: 10
    rightPadding: 10
    topPadding: 0
    bottomPadding: 0
    labelSize: 12
    cornerRadius: 8
    background: Rectangle {
        radius: smallKey.cornerRadius
        color: !smallKey.enabled ? Theme.key : smallKey.accent ? (smallKey.hovered || smallKey.down ? Theme.accentHover : Theme.accent) : smallKey.rest
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: !smallKey.accent
            color: smallKey.wash
            opacity: smallKey.enabled && (smallKey.hovered || smallKey.down || smallKey.visualFocus) ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fast
                }
            }
        }
    }
}
