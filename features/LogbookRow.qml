pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../core/day.js" as DayText
import "../components" as C

// One work order in a Logbook list: its box, magnitude bars, time, title and what is attached to it.
Rectangle {
    id: row
    required property var order
    required property bool current
    required property bool marked
    required property bool listFocus
    required property real now
    signal clicked(bool extend)
    signal doubleClicked()
    signal toggled()
    readonly property bool cleared: order.doneAt !== null && order.doneAt !== undefined
    readonly property bool late: !cleared && order.dueAt !== null && order.dueAt < (order.allDay ? new Date(now).setHours(0, 0, 0, 0) : now)
    implicitHeight: 30
    radius: 4
    color: current && listFocus ? Theme.selection : marked ? Theme.selectionHover : hover.hovered ? Theme.hover : "transparent"
    border.width: current && !listFocus ? 1 : 0
    border.color: Theme.border
    Accessible.role: Accessible.ListItem
    Accessible.name: order.text + (cleared ? ", cleared" : "") + (late ? ", overdue" : "") + (order.priority > 1 ? ", magnitude " + order.priority : "")
    HoverHandler {
        id: hover
    }
    TapHandler {
        acceptedModifiers: Qt.NoModifier
        onTapped: row.clicked(false)
        onDoubleTapped: row.doubleClicked()
    }
    TapHandler {
        acceptedModifiers: Qt.ShiftModifier
        onTapped: row.clicked(true)
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.gapS
        anchors.rightMargin: Theme.gapS
        spacing: Theme.gapS
        // The box: a ring while open, a filled stone once cleared.
        Rectangle {
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            radius: 7
            color: row.cleared ? Theme.accent : "transparent"
            border.width: 1.5
            border.color: row.cleared ? Theme.accent : row.late ? Theme.warning : Theme.muted
            TapHandler {
                onTapped: row.toggled()
            }
        }
        // Magnitude is bars, never colour alone: M2 one bar, M4 three.
        Row {
            Layout.preferredWidth: 20
            spacing: 2
            Repeater {
                model: 3
                Rectangle {
                    id: bar
                    required property int index
                    width: 4
                    height: 12
                    radius: 1
                    color: bar.index < row.order.priority - 1 ? (row.order.priority === 4 ? Theme.accent2 : Theme.warning) : Theme.border
                }
            }
        }
        C.Label {
            visible: row.order.dueAt !== null && row.order.dueAt !== undefined && !row.order.allDay
            text: Qt.formatDateTime(new Date(row.order.dueAt || 0), ShellState.timeFormat)
            font.family: Theme.instrument
            font.pixelSize: Theme.small
            color: row.late ? Theme.warning : Theme.muted
        }
        C.Label {
            Layout.fillWidth: true
            text: row.order.text
            color: row.cleared ? Theme.muted : Theme.text
            font.strikeout: row.cleared
        }
        C.Label {
            visible: !!row.order.site
            text: "#" + row.order.site + (row.order.section ? "/" + row.order.section : "")
            color: Theme.muted
            font.pixelSize: Theme.small
        }
        C.Label {
            visible: row.order.tags.length > 0
            text: row.order.tags.map(tag => "@" + tag).join(" ")
            color: Theme.muted
            font.pixelSize: Theme.small
        }
        C.Label {
            visible: row.order.openSubOrders > 0
            text: "▸ " + row.order.openSubOrders
            color: Theme.muted
            font.pixelSize: Theme.small
            Accessible.name: row.order.openSubOrders + " open sub-orders"
        }
        C.Label {
            visible: !!row.order.rule
            text: "↻"
            color: Theme.muted
            font.pixelSize: Theme.small
            Accessible.name: "repeats"
        }
        C.Label {
            visible: row.order.deadlineAt !== null && row.order.deadlineAt !== undefined
            text: "⚑ " + DayText.dayLabel(row.order.deadlineAt || 0, row.now)
            color: row.order.deadlineAt < row.now && !row.cleared ? Theme.warning : Theme.muted
            font.pixelSize: Theme.small
        }
        C.Label {
            visible: row.cleared
            text: "CLEARED " + Qt.formatDateTime(new Date(row.order.doneAt || 0), ShellState.timeFormat)
            color: Theme.muted
            font.family: Theme.instrument
            font.pixelSize: Theme.caption
        }
    }
}
