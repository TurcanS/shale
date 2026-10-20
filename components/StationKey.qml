import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"

// A hardware key: raised, pressed in when chosen; the accent edge shows keyboard focus.
AbstractButton {
    id: key
    property bool lit: false
    implicitHeight: 30
    implicitWidth: Math.max(40, keyText.implicitWidth + 20)
    Layout.fillWidth: true
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    contentItem: Text {
        id: keyText
        text: key.text
        font.family: Theme.instrument
        font.pixelSize: Theme.label
        color: key.lit ? Theme.accent : Theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 4
        color: key.down ? Theme.background : key.hovered ? Theme.hover : Theme.raised
        border.width: key.activeFocus ? 1.5 : 1
        border.color: key.activeFocus ? Theme.accent : Theme.border
        // The key's lower lip; it disappears while pressed.
        Rectangle {
            visible: !key.down
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 2
            radius: 2
            color: Theme.background
        }
    }
}
