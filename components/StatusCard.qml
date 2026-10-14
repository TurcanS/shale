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
    implicitHeight: content.implicitHeight + 2 * Theme.gapL
    radius: Theme.controlRadius
    color: Theme.surface
    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.gapL
        spacing: Theme.gapM
        RowLayout {
            spacing: Theme.gapM
            GlyphTile {
                size: 44
                glyph: root.glyph
                positive: root.positive
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapXs
                Label {
                    text: root.title
                    font.pixelSize: root.level >= 0 ? Theme.heading + 8 : Theme.heading
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
                color: root.level < 0.15 ? Theme.warning : Theme.fill
                Behavior on width { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Theme.fast } }
            }
        }
    }
}
