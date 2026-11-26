import QtQuick
import "../core"
import "../components" as C

// M and S on a channel strip.
C.Button {
    id: stripKey
    property color onColor: Theme.raisedOnKey
    property color onText: Theme.accentText
    implicitWidth: 26
    implicitHeight: 22
    padding: 0
    labelSize: 11
    cornerRadius: 6
    foreground: selected ? onText : Theme.textMuted
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: selected
    // M and S light like the lamps on a desk channel strip.
    onSelectedChanged: if (selected) lamp.flash()
    background: Rectangle {
        radius: stripKey.cornerRadius
        color: stripKey.selected ? stripKey.onColor : stripKey.hovered || stripKey.down || stripKey.visualFocus ? Theme.keyHover : Theme.keyTile
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        C.Raise {
            resting: !stripKey.selected
            sunk: stripKey.sunk
        }
        C.WarmUp {
            id: lamp
            anchors.fill: parent
            radius: parent.radius
            peak: 0.45
        }
    }
}
