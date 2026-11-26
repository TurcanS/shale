import QtQuick
import "../core"
import "../components" as C

BarLiveChip {
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    shown: ShellState.presentation
    implicitWidth: 24
    padding: 0
    leftPadding: 0
    rightPadding: 0
    hint: "Stay awake is on"
    tooltip: bar.tooltip
    onClicked: ShellState.presentation = false
    contentItem: Item {
        C.Icon {
            anchors.centerIn: parent
            name: "moon"
            size: 13
            color: Theme.accentText
        }
    }
}
