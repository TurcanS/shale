pragma ComponentBehavior: Bound
import QtQuick
import "../services"
import "../components" as C

// Instrument checks: a small key for each routine due today, lit once checked in. Only on days one is due.
Flow {
    id: row
    visible: Day.routinesDue.length > 0
    spacing: 4
    C.StationText {
        text: "Checks"
        width: row.width
    }
    Repeater {
        model: Day.routinesDue
        C.StationKey {
            id: key
            required property var modelData
            lit: modelData.checkedToday
            implicitHeight: 24
            text: (modelData.checkedToday ? "● " : "○ ") + (modelData.name.length > 12 ? modelData.name.slice(0, 11) + "…" : modelData.name)
            Accessible.name: "Check in " + modelData.name + (modelData.checkedToday ? ", done today" : "")
            onClicked: Day.checkRoutine(modelData.id, !modelData.checkedToday)
        }
    }
}
