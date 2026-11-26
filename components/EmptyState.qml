import QtQuick
import QtQuick.Layouts
import "../core"

ColumnLayout {
    id: root
    property string title: "Nothing here yet"
    property string description: ""
    property string glyph: "grid"
    spacing: Theme.gapS
    GlyphTile {
        size: 48
        glyph: root.glyph
        glyphColor: Theme.textDim
        color: Theme.module
        radius: Theme.radiusCard + 2
        Layout.alignment: Qt.AlignHCenter
    }
    Label {
        text: title
        font.pixelSize: Theme.body + 1
        font.weight: Font.DemiBold
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
    Label {
        visible: root.description !== ""
        text: description
        color: Theme.textDim
        font.pixelSize: Theme.label
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true
    }
}
