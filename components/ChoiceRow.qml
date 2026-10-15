import QtQuick
import QtQuick.Layouts
import "../core"
import "." as C

// A setting with a few choices: its label (and a line about it) beside a Segmented control.
RowLayout {
    id: root
    property string label: ""
    property string description: ""
    property var model: []
    property var current: null
    signal activated(var key)
    Layout.fillWidth: true
    spacing: Theme.gapM
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        C.Label {
            text: root.label
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        C.Caption {
            visible: root.description !== ""
            text: root.description
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
    C.Segmented {
        fill: false
        model: root.model
        current: root.current
        Accessible.name: root.label
        onActivated: key => root.activated(key)
    }
}
