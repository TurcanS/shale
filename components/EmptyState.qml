import QtQuick
import QtQuick.Layouts
import "../core"

ColumnLayout {
    id: root
    property string title: "Nothing here yet"
    property string description: ""
    property string glyph: "grid"
    spacing: 8
    Rectangle {
        Layout.preferredWidth: 48
        Layout.preferredHeight: 48
        Layout.alignment: Qt.AlignHCenter
        radius: Theme.controlRadius
        color: Theme.surface
        Icon {
            anchors.centerIn: parent
            name: root.glyph
            size: 20
            opacity: 0.65
        }
    }
    Label {
        text: title
        font.pixelSize: Math.max(16, Theme.body + 2)
        font.weight: Font.DemiBold
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
    Label {
        visible: root.description !== ""
        text: description
        color: Theme.muted
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true
    }
}
