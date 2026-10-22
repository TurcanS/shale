pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/day.js" as DayText
import "../core/logbook.js" as Book
import "../services"
import "../components" as C

// The detail sheet of the selected order, sliding over the right third of the Logbook.
Rectangle {
    id: sheet
    // The order shown, or null.
    property var order: null
    property real now: Date.now()
    // Open means shown; the position follows it so a reversal carries on from where the slide is.
    property bool shown: false
    readonly property bool editing: titleField.activeFocus || notesField.activeFocus
    signal closed()
    signal confirmed()
    signal released()
    readonly property var subOrders: order ? Day.orders.filter(item => item.parentId === order.id) : []
    // Lets go of the fields, so keys reach the Logbook again.
    function release() {
        titleField.focus = false;
        notesField.focus = false;
    }
    function focusTitle() {
        titleField.forceActiveFocus();
    }
    function save(fields) {
        if (order)
            Day.update(order.id, fields);
    }
    function stamp(at) {
        return at === null || at === undefined ? "—" : DayText.dayLabel(at, now) + " " + Qt.formatDateTime(new Date(at), ShellState.timeFormat);
    }
    function dueText(item) {
        if (item.dueAt === null || item.dueAt === undefined)
            return "—";
        return DayText.dayLabel(item.dueAt, now) + (item.allDay ? "" : " " + Qt.formatDateTime(new Date(item.dueAt), ShellState.timeFormat));
    }
    function alertText(alert) {
        if (alert.at)
            return stamp(alert.at);
        return alert.beforeMin ? alert.beforeMin + " min before" : "at the due time";
    }
    visible: x < parent.width
    width: Math.round(parent.width / 3)
    height: parent.height
    x: shown ? parent.width - width : parent.width
    Behavior on x {
        NumberAnimation {
            duration: Theme.enter
            easing.type: Easing.OutCubic
        }
    }
    color: Theme.panel
    border.width: 1
    border.color: Theme.border
    clip: true
    onShownChanged: if (!shown) titleField.focus = false
    Keys.onEscapePressed: sheet.closed()
    MouseArea {
        anchors.fill: parent
        onWheel: wheel => wheel.accepted = true
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapM
        spacing: Theme.gapS
        RowLayout {
            Layout.fillWidth: true
            C.StationText {
                text: "Work order"
                Layout.fillWidth: true
            }
            C.StationKey {
                text: sheet.order && sheet.order.doneAt ? "Reopen" : "Clear"
                Layout.fillWidth: false
                implicitWidth: 72
                onClicked: sheet.confirmed()
            }
            C.StationKey {
                text: "Close"
                Layout.fillWidth: false
                implicitWidth: 64
                onClicked: sheet.closed()
            }
        }
        C.Field {
            id: titleField
            Layout.fillWidth: true
            implicitHeight: 34
            text: sheet.order ? sheet.order.text : ""
            placeholderText: "Title"
            Accessible.name: "Title"
            Keys.onEscapePressed: {
                text = sheet.order ? sheet.order.text : "";
                sheet.closed();
            }
            onAccepted: {
                if (text.trim() && sheet.order && text.trim() !== sheet.order.text)
                    sheet.save({text: text.trim()});
                sheet.released();
            }
        }
        // Magnitude M1 to M4 as four keys.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapXs
            Repeater {
                model: 4
                C.StationKey {
                    required property int index
                    text: "M" + (index + 1)
                    lit: sheet.order !== null && sheet.order.priority === index + 1
                    Accessible.name: "Magnitude " + (index + 1)
                    onClicked: sheet.save({priority: index + 1})
                }
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Theme.gapM
            rowSpacing: 2
            Repeater {
                model: sheet.order ? [
                    ["Site", sheet.order.site ? sheet.order.site + (sheet.order.section ? " / " + sheet.order.section : "") : "Intake"],
                    ["Tags", sheet.order.tags.length ? sheet.order.tags.map(tag => "@" + tag).join(" ") : "—"],
                    ["Due", sheet.dueText(sheet.order)],
                    ["Deadline", sheet.order.deadlineAt ? DayText.dayLabel(sheet.order.deadlineAt, sheet.now) : "—"],
                    ["Duration", sheet.order.durationMin ? sheet.order.durationMin + " min" : "—"],
                    ["Repeat", sheet.order.rule ? sheet.order.rule : "—"],
                    ["Alerts", sheet.order.alerts.length ? sheet.order.alerts.map(sheet.alertText).join(", ") : "—"],
                    ["Quiet", sheet.order.quietSeconds ? Math.round(sheet.order.quietSeconds / 60) + " min logged" : "—"],
                    ["Created", sheet.stamp(sheet.order.createdAt)],
                    ["Cleared", sheet.stamp(sheet.order.doneAt)]
                ] : []
                delegate: Item {
                    id: fact
                    required property var modelData
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    implicitHeight: 20
                    C.StationText {
                        text: fact.modelData[0]
                        width: 70
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.Label {
                        x: 78
                        width: parent.width - 78
                        anchors.verticalCenter: parent.verticalCenter
                        text: fact.modelData[1]
                        font.pixelSize: Theme.small
                    }
                }
            }
        }
        C.StationText {
            text: "Sub-orders"
            visible: sheet.subOrders.length > 0
        }
        Repeater {
            model: sheet.subOrders
            C.Label {
                required property var modelData
                Layout.fillWidth: true
                text: (modelData.doneAt ? "● " : "○ ") + modelData.text
                color: modelData.doneAt ? Theme.muted : Theme.text
                font.pixelSize: Theme.small
            }
        }
        C.StationText {
            text: "Notes"
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextArea {
                id: notesField
                text: sheet.order && sheet.order.notes ? sheet.order.notes : ""
                wrapMode: TextEdit.Wrap
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.small
                placeholderText: "Plain text. Ctrl+Enter saves."
                placeholderTextColor: Theme.disabled
                selectionColor: Theme.selectionHover
                Accessible.name: "Notes"
                background: Rectangle {
                    radius: 4
                    color: Theme.background
                    border.width: 1
                    border.color: notesField.activeFocus ? Theme.accent : Theme.border
                }
                Keys.onEscapePressed: {
                    text = sheet.order && sheet.order.notes ? sheet.order.notes : "";
                    sheet.released();
                }
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                        sheet.save({notes: text});
                        sheet.released();
                        event.accepted = true;
                    }
                }
                onActiveFocusChanged: {
                    if (!activeFocus && sheet.order && text !== (sheet.order.notes || ""))
                        sheet.save({notes: text});
                }
            }
        }
        // The notes stay plain text to edit; their https:// links open from keys under them.
        Flow {
            Layout.fillWidth: true
            spacing: Theme.gapS
            visible: links.count > 0
            Repeater {
                id: links
                model: Book.links(notesField.text, 3)
                C.StationKey {
                    required property string modelData
                    text: "↗ " + modelData.replace(/^https:\/\//, "").slice(0, 40)
                    Accessible.name: "Open link " + modelData
                    onClicked: ShellState.openUrl(modelData)
                }
            }
        }
    }
}
