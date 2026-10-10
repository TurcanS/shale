import QtQuick
import QtQuick.Controls as Controls
import "../core"

Controls.ScrollBar {
    id: root
    policy: Controls.ScrollBar.AsNeeded
    minimumSize: 0.12
    padding: 2
    implicitWidth: 8
    hoverEnabled: true
    contentItem: Rectangle {
        implicitWidth: 4
        implicitHeight: 24
        radius: 2
        color: root.pressed ? Theme.text : root.hovered ? Theme.muted : Theme.disabled
        opacity: root.size <= 0 || root.size >= 1 || root.policy === Controls.ScrollBar.AlwaysOff ? 0 : root.active || root.hovered || root.pressed ? 0.65 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    background: Item {}
}
