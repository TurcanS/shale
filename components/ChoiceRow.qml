import QtQuick
import "../core"
import "." as C

// A setting with a few choices: a group row with its label (and a line about it) beside a Segmented control, or
// above it when stacked.
C.SettingRow {
    id: root
    property var model: []
    property var current: null
    signal activated(var key)
    C.Segmented {
        fill: root.stacked
        // Sits on a grouped settings row, a step lighter than a module.
        trackColor: Theme.well
        segmentHeight: 32
        model: root.model
        current: root.current
        Accessible.name: root.label
        onActivated: key => root.activated(key)
    }
}
