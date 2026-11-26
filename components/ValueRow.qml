import QtQuick
import QtQuick.Layouts
import "../core"
import "." as C

// A value shown at the right of a row, for facts rather than choices.
SettingRow {
    id: valueRow
    property string value: ""
    property color valueColor: Theme.textSecondary
    property bool mono: false
    C.Label {
        text: valueRow.value
        color: valueRow.valueColor
        font.family: valueRow.mono ? Theme.mono : Theme.font
        font.pixelSize: valueRow.mono ? Theme.small : Theme.label
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.WordWrap
        Layout.maximumWidth: 320
    }
}
