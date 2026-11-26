import QtQuick
import "../core"
import "../components" as C

// The keyboard layout the password will be typed in, as a chip beside what's playing. It only shows the layout:
// switching stays on the keyboard's own shortcut.
Rectangle {
    id: root
    readonly property var layouts: ShellState.keyboard.layouts || []
    readonly property var current: layouts[ShellState.keyboard.index] || null
    visible: !!current
    implicitWidth: code.implicitWidth + 24
    implicitHeight: 32
    radius: height / 2
    color: Theme.tint(Theme.caseColor, 0.55)
    Accessible.role: Accessible.StaticText
    Accessible.name: "Keyboard layout, " + (ShellState.keyboard.name || code.text)
    C.Label {
        id: code
        anchors.centerIn: parent
        text: root.current ? root.current.code.toUpperCase().slice(0, 3) : ""
        color: Theme.tint(Theme.text, 0.75)
        font.pixelSize: 13
        elide: Text.ElideNone
    }
}
