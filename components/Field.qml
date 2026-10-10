import QtQuick
import QtQuick.Controls
import "../core"

TextField {
    color: enabled ? Theme.text : Theme.disabled
    placeholderTextColor: Theme.disabled
    font.family: Theme.font
    font.pixelSize: Theme.body
    selectionColor: Theme.selectionHover
    selectedTextColor: Theme.text
    implicitHeight: 44
    leftPadding: 14
    rightPadding: 14
    selectByMouse: true
    verticalAlignment: TextInput.AlignVCenter
    Accessible.name: placeholderText
    background: Rectangle {
        radius: Theme.controlRadius
        color: parent.activeFocus ? Theme.raised : Theme.surface
        border.width: 0
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
    }
}
