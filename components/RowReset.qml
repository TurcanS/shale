import QtQuick
import "../core"
import "." as C

// A small key beside a setting's name, shown only while the setting differs from how Shale comes: it puts that one
// setting back, with Undo in the message. The dot it draws also marks the row as changed at a glance.
C.Button {
    id: root
    property string key: ""
    property string name: ""
    readonly property bool changed: key !== "" && ShellState.differs(key)
    visible: changed
    flat: true
    glyph: "refresh"
    implicitWidth: 22
    implicitHeight: 22
    cornerRadius: 6
    foreground: hovered || visualFocus ? Theme.text : Theme.accentText
    hint: "Back to how Shale comes"
    Accessible.name: "Reset " + (name || key)
    onClicked: ShellState.resetSettings([key], () => ShellState.message((name || "Setting") + " reset", "success", {label: "Undo", run: () => ShellState.restoreSettings()}))
}
