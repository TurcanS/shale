import QtQuick
import "../core"
import "../services"

BarStatusPart {
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    glyph: "sliders"
    selected: bar.controlActive("")
    hint: Updates.available ? "Control · Update available" : "Control"
    tooltip: bar.tooltip
    Accessible.name: hint
    onClicked: bar.toggleControl("")
    // A newer Shale is waiting; Control's first row says what it changes.
    Rectangle {
        visible: Updates.available
        z: 2
        x: parent.width - width - 3
        y: 4
        width: 6
        height: 6
        radius: 3
        color: Theme.accent
    }
}
