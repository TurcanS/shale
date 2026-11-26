import QtQuick
import "../core"

BarKey {
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property var layouts: ShellState.keyboard.layouts || []
    readonly property var current: layouts[ShellState.keyboard.index] || null
    shown: layouts.length > 1
    leftPadding: 10
    rightPadding: 10
    labelSize: 12
    text: current ? current.code.toUpperCase().slice(0, 3) : ""
    hint: (ShellState.keyboard.name || "Keyboard layout") + "\n" + layouts.map((l, i) => (i === ShellState.keyboard.index ? "● " : "○ ") + l.code + (l.variant ? " (" + l.variant + ")" : "")).join("\n") + "\nClick for the next layout"
    tooltip: bar.tooltip
    Accessible.name: "Keyboard layout, " + (ShellState.keyboard.name || text)
    onClicked: ShellState.nextKeyboardLayout()
}
