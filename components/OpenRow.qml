import QtQuick
import "." as C

// A row whose control is one button that opens something.
SettingRow {
    id: openRow
    property string action: "Open"
    property string glyph: ""
    signal opened()
    C.Button {
        text: openRow.action
        glyph: openRow.glyph
        implicitHeight: 32
        onClicked: openRow.opened()
    }
}
