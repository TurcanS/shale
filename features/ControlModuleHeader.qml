import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// A module's title row: title and a quiet note, then whatever controls it holds.
RowLayout {
    id: moduleHeader
    property string title: ""
    property string note: ""
    property bool large: false
    property bool noteRight: false
    Layout.fillWidth: true
    Layout.minimumHeight: 28
    spacing: Theme.gapS
    C.Label {
        text: moduleHeader.title
        font.pixelSize: moduleHeader.large ? 15 : 14
        font.weight: moduleHeader.large ? 650 : Font.DemiBold
        elide: Text.ElideNone
    }
    C.Label {
        text: moduleHeader.note
        color: Theme.textDim
        font.pixelSize: 12
        horizontalAlignment: moduleHeader.noteRight ? Text.AlignRight : Text.AlignLeft
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.leftMargin: 2
    }
}
