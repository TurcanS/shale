import QtQuick
import QtQuick.Layouts
import "../core"

// A module with a large glyph tile, a headline and an optional level meter (accent from soft to full, danger when low).
Rectangle {
    id: root
    property string title: ""
    property string subtitle: ""
    property string glyph: "info"
    property real level: -1
    property bool positive: false
    implicitHeight: content.implicitHeight + 2 * Theme.gapL
    radius: Theme.radiusModule
    color: Theme.module
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
                    font.pixelSize: root.level >= 0 ? Theme.heading + 6 : Theme.heading
                    font.weight: 650
                    font.features: {"tnum": 1}
                    Layout.fillWidth: true
                }
                Label {
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    font.pixelSize: Theme.label
                    color: Theme.textDim
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
        Rectangle {
            visible: root.level >= 0
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Theme.key
            Rectangle {
                id: levelFill
                readonly property bool low: root.level < 0.15
                width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.level)))
                height: parent.height
                radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: levelFill.low ? Theme.dangerSoft : Theme.accentSoft }
                    GradientStop { position: 1; color: levelFill.low ? Theme.danger : Theme.accent }
                }
                Behavior on width { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
            }
        }
    }
}
