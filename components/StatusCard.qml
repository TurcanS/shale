import QtQuick
import QtQuick.Layouts
import "../core"

Rectangle {
    id: root
    property string title: ""
    property string subtitle: ""
    property string glyph: "info"
    property real level: -1
    property bool positive: false
    implicitHeight: content.implicitHeight + 32
    radius: Theme.controlRadius
    color: Theme.surface
    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 14
        RowLayout {
            spacing: 14
            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 12
                color: Theme.raised
                Icon { anchors.centerIn: parent; name: root.glyph; size: 22 }
                Rectangle {
                    visible: root.positive
                    width: 7; height: 7; radius: 3.5
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    color: Theme.success
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label {
                    text: root.title
                    font.pixelSize: root.level >= 0 ? 32 : 22
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                Label {
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    font.pixelSize: Theme.label
                    color: Theme.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
        Rectangle {
            visible: root.level >= 0
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: Theme.raised
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.level))
                height: parent.height
                radius: 4
                color: root.level < 0.15 ? Theme.warning : Theme.activityLevel3
                Behavior on width { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Theme.fast } }
            }
        }
    }
}
