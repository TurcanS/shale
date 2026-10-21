pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../core/day.js" as DayText
import "../core/routines.js" as RoutineText
import "../services"
import "../components" as C

// Instrument checks: the routines, checking in, each one's current and best streak and a heat map of the last 26 weeks.
Item {
    id: view
    property int cursor: 0
    property real now: Date.now()
    readonly property var list: Day.routines
    readonly property var current: cursor >= 0 && cursor < list.length ? list[cursor] : null
    readonly property int first: (ShellState.firstDayOfWeek + 6) % 7
    readonly property var parsed: addField.text.trim() ? view.read(addField.text) : null
    readonly property bool typing: addField.activeFocus

    // What the text means: a name and a schedule ("water every mon, wed", "run 3 times a week at 7:00 remind me"), or the reason it is not one.
    function read(text) {
        const split = RoutineText.split(text);
        if (split.error)
            return {error: split.error};
        const order = DayText.capture(split.text, view.now, {});
        if (!order || order.error)
            return {error: order ? order.error : "Name the routine."};
        const alert = order.alerts.length ? order.alerts[0] : null;
        const at = alert && alert.at !== undefined ? new Date(alert.at) : order.dueAt !== null && !order.allDay ? new Date(order.dueAt) : null;
        return {name: order.text, rule: split.times ? "TIMES=" + split.times : order.rule || "FREQ=DAILY",
                minute: at ? at.getHours() * 60 + at.getMinutes() : null, alert: alert !== null && alert.at !== undefined && at !== null, error: null};
    }
    function submit() {
        const routine = parsed;
        if (!routine || routine.error)
            return;
        const text = addField.text;
        addField.text = "";
        const fields = {name: routine.name, rule: routine.rule};
        if (routine.minute !== null) {
            fields.minute = routine.minute;
            fields.alert = routine.alert;
        }
        Day.addRoutine(fields, (result, error) => view.added(error, text));
    }
    function added(error, text) {
        if (!error)
            return;
        addField.text = text;
        ShellState.message(error.message, "error");
    }
    function toggle(routine) {
        Day.checkRoutine(routine.id, !routine.checkedToday);
    }
    // Keys for the list; the Logbook passes them on while this view is shown. True when handled.
    function handle(event) {
        if (event.key === Qt.Key_Up) {
            cursor = Math.max(0, cursor - 1);
        } else if (event.key === Qt.Key_Down) {
            cursor = Math.min(list.length - 1, cursor + 1);
        } else if (event.key === Qt.Key_Space && current) {
            toggle(current);
        } else if (event.key === Qt.Key_Delete && current) {
            Day.removeRoutine(current.id);
            cursor = Math.max(0, cursor - 1);
        } else if (event.key === Qt.Key_Q || event.key === Qt.Key_Plus) {
            addField.forceActiveFocus();
        } else {
            return false;
        }
        return true;
    }
    function release() {
        addField.focus = false;
    }
    Component.onCompleted: Day.loadRoutines()
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gapS
        C.Label {
            visible: view.list.length === 0
            Layout.fillWidth: true
            text: "No routines yet. Type one below: \"water every day\", \"gym every mon, wed, fri\", \"run 3 times a week\"."
            color: Theme.muted
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: view.list
            Rectangle {
                id: row
                required property var modelData
                required property int index
                Layout.fillWidth: true
                height: 32
                radius: 4
                color: row.index === view.cursor ? Theme.selection : "transparent"
                Accessible.name: row.modelData.name + ", " + RoutineText.label(row.modelData.rule) + ", streak " + RoutineText.streakText(row.modelData)
                TapHandler {
                    onTapped: view.cursor = row.index
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.gapS
                    anchors.rightMargin: Theme.gapS
                    spacing: Theme.gapS
                    Rectangle {
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        radius: 7
                        color: row.modelData.checkedToday ? Theme.accent : "transparent"
                        border.width: 1.5
                        border.color: row.modelData.checkedToday ? Theme.accent : row.modelData.dueToday ? Theme.text : Theme.muted
                        TapHandler {
                            margin: 8
                            onTapped: view.toggle(row.modelData)
                        }
                    }
                    C.Label {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        color: row.modelData.dueToday || row.modelData.checkedToday ? Theme.text : Theme.muted
                    }
                    C.Label {
                        text: RoutineText.label(row.modelData.rule) + (row.modelData.minute !== null ? " · " + String(Math.floor(row.modelData.minute / 60)).padStart(2, "0") + ":" + String(row.modelData.minute % 60).padStart(2, "0") : "")
                        color: Theme.muted
                        font.pixelSize: Theme.small
                    }
                    C.Label {
                        text: RoutineText.streakText(row.modelData) + "  best " + row.modelData.best
                        font.family: Theme.instrument
                        font.pixelSize: Theme.small
                        color: Theme.accent
                    }
                }
            }
        }
        C.StationText {
            visible: view.current !== null
            text: view.current ? view.current.name + " · last 26 weeks" : ""
        }
        Row {
            visible: view.current !== null
            spacing: 2
            Repeater {
                model: view.current ? RoutineText.heat(view.current.history, Day.today(), 26, view.first) : []
                Column {
                    id: week
                    required property var modelData
                    spacing: 2
                    Repeater {
                        model: week.modelData
                        Rectangle {
                            required property var modelData
                            width: 10
                            height: 10
                            radius: 2
                            visible: !modelData.future
                            color: modelData.lit ? Theme.accent : Theme.surface
                            Accessible.name: modelData.date + (modelData.lit ? ", checked" : "")
                        }
                    }
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
        C.Field {
            id: addField
            Layout.fillWidth: true
            implicitHeight: 32
            font.family: Theme.mono
            font.pixelSize: Theme.label
            placeholderText: "new routine: \"water every day\" · \"run 3 times a week\" · \"vitamins 9:00 remind 9:00\""
            Keys.onEscapePressed: event => {
                view.release();
                event.accepted = false;
            }
            Keys.onReturnPressed: view.submit()
            Keys.onEnterPressed: view.submit()
        }
        C.Label {
            visible: addField.text !== ""
            Layout.fillWidth: true
            font.pixelSize: Theme.small
            elide: Text.ElideRight
            color: view.parsed && view.parsed.error ? Theme.warning : Theme.muted
            text: !view.parsed ? "" : view.parsed.error ? view.parsed.error : "Routine · " + view.parsed.name + " · " + RoutineText.label(view.parsed.rule)
                  + (view.parsed.minute !== null ? " · " + String(Math.floor(view.parsed.minute / 60)).padStart(2, "0") + ":" + String(view.parsed.minute % 60).padStart(2, "0") : "")
                  + (view.parsed.alert ? " · alert" : "")
        }
        C.Label {
            Layout.fillWidth: true
            text: "↑↓ move · Space check in · Q new · Delete remove · Esc back"
            color: Theme.disabled
            font.family: Theme.instrument
            font.pixelSize: Theme.caption
        }
    }
}
