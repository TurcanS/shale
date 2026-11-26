import QtQuick
import "../core"

// A 28 px round chip for a quick choice or a small toggle: a hairline edge at rest (or a `rest` fill), and when
// selected ("on") the accent wash, accent edge and accent text.
Button {
    id: root
    property color rest: "transparent"
    implicitHeight: 28
    leftPadding: glyph !== "" && text !== "" ? 10 : 12
    rightPadding: 12
    topPadding: 0
    bottomPadding: 0
    labelSize: 12
    cornerRadius: height / 2
    foreground: !enabled ? Theme.textFaint : selected ? Theme.accentText : Theme.text
    background: Rectangle {
        radius: root.cornerRadius
        color: root.selected ? Theme.accentSoft : root.rest
        border.width: 1
        border.color: root.selected ? Theme.accentLine : Theme.edge
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.wash
            opacity: root.enabled && (root.hovered || root.down || root.visualFocus) ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fast
                }
            }
        }
    }
}
