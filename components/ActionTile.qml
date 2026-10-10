import QtQuick
import QtQuick.Layouts
import "../core"

Button {
    id: root
    property string subtitle: ""
    implicitHeight: Math.max(104, contentItem.implicitHeight + topPadding + bottomPadding)
    padding: 14
    background: Rectangle {
        radius: Theme.controlRadius
        color: root.down || root.hovered || root.visualFocus ? (root.selected ? Theme.selectionHover : Theme.hover) : root.selected ? Theme.selection : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    contentItem: ColumnLayout {
        opacity: root.enabled ? 1 : 0.45
        spacing: 8
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 10
            color: root.selected ? Theme.selectionHover : Theme.raised
            Icon {
                anchors.centerIn: parent
                name: root.glyph
                invert: false
                size: 18
            }
        }
        Label {
            Layout.fillWidth: true
            text: root.text
            horizontalAlignment: Text.AlignHCenter
            color: root.danger ? Theme.danger : Theme.text
            font.weight: Font.Medium
        }
        Label {
            visible: root.subtitle !== ""
            Layout.fillWidth: true
            text: root.subtitle
            horizontalAlignment: Text.AlignHCenter
            color: Theme.muted
            font.pixelSize: Theme.small
        }
    }
}
