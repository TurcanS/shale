import QtQuick
import QtQuick.Layouts
import "../core"

// A labelled headline number with an optional note, for summary rows.
Card {
    id: stat
    property string label: ""
    property string value: ""
    property string note: ""
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.preferredHeight: Math.max(64, content.implicitHeight + 2 * Theme.gapM - 4)
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.gapM - 2
        spacing: 1
        Label { text: stat.label; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true }
        Label { text: stat.value; font.family: Theme.mono; font.pixelSize: Theme.body + 4; font.weight: Font.DemiBold; Layout.fillWidth: true }
        Caption { visible: stat.note !== ""; text: stat.note; color: Theme.disabled; Layout.fillWidth: true }
    }
}
