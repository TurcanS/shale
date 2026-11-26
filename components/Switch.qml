import QtQuick
import "../core"

// The 40×22 switch on its own, for module headers (see SwitchTrack). Name it with `hint`.
Button {
    id: root
    implicitWidth: 40
    implicitHeight: 22
    padding: 0
    cornerRadius: 11
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: selected
    pressDepth: 0
    background: SwitchTrack {
        on: root.selected
        hot: root.hovered || root.visualFocus || root.down
        opacity: root.enabled ? 1 : Theme.disabledOpacity
    }
    contentItem: Item {}
}
