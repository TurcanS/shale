import QtQuick
import QtQuick.Layouts
import "../core"

// A labelled headline number with an optional note, for summary rows: a stat tile, one step below a module.
// Pages can size it: System's small tiles, Activity's large cards on the module surface.
Card {
    id: stat
    color: Theme.moduleAlt
    radius: Theme.radiusCard
    property string label: ""
    property string value: ""
    property string note: ""
    property int valueSize: Theme.body + 8
    property int noteSize: Theme.caption
    property color noteColor: Theme.textDim
    property int inset: Theme.gapM - 2
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.preferredHeight: Math.max(64, content.implicitHeight + 2 * inset)
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: stat.inset
        spacing: 1
        Label { text: stat.label; font.pixelSize: Theme.small; color: Theme.textDim; Layout.fillWidth: true }
        Label { text: stat.value; font.pixelSize: stat.valueSize; font.weight: 650; font.features: {"tnum": 1}; Layout.fillWidth: true }
        Caption { visible: stat.note !== ""; text: stat.note; font.pixelSize: stat.noteSize; color: stat.noteColor; Layout.fillWidth: true }
    }
}
