pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/day.js" as DayText
import "../services"
import "../components" as C

// The shift report: what was cleared today, what was not (with the carry-over choices, so tomorrow starts clean), the
// time recorded, one line of notes for the day, and the last four weeks as columns.
Item {
    id: report
    property real now: Date.now()
    property var filed: null
    property var activity: null
    // Order id to choice, for the orders still open.
    property var choices: ({})
    readonly property var cleared: filed ? filed.cleared : []
    readonly property var open: filed ? filed.open.filter(order => !order.parentId) : []
    readonly property var momentum: Day.momentum
    readonly property real recorded: activity ? activity.active + activity.watching : 0
    readonly property int quietMinutes: Math.round(cleared.reduce((sum, order) => sum + (order.quietSeconds || 0), 0) / 60)
    readonly property string tomorrow: {
        const day = new Date(now);
        day.setDate(day.getDate() + 1);
        return day.getFullYear() + "-" + String(day.getMonth() + 1).padStart(2, "0") + "-" + String(day.getDate()).padStart(2, "0");
    }
    readonly property var siteNames: {
        const names = [];
        (momentum && momentum.perDay ? momentum.perDay : []).forEach(day => Object.keys(day.bySite).forEach(name => {
            if (names.indexOf(name) < 0)
                names.push(name);
        }));
        return names.sort();
    }
    readonly property int peak: Math.max(1, ...(momentum && momentum.perDay ? momentum.perDay.map(day => day.cleared) : [1]))
    readonly property int quietPeak: Math.max(1, ...(momentum && momentum.perDay ? momentum.perDay.map(day => day.quietMinutes || 0) : [1]))
    signal changed()

    function load() {
        now = Date.now();
        Day.report((result, error) => report.loaded(result, error));
        Backend.request("activity.day", {date: Day.today()}, (result, error) => report.activityLoaded(result, error));
        Day.loadMomentum();
    }
    function loaded(result, error) {
        if (error)
            return;
        filed = result;
        const kept = {};
        open.forEach(order => kept[order.id] = {action: "keep", days: 0});
        choices = kept;
        noteField.text = result.day.note || "";
    }
    function activityLoaded(result, error) {
        if (!error)
            activity = result;
    }
    function choose(order, action, days) {
        const copy = Object.assign({}, choices);
        copy[order.id] = {action: action, days: days || 0};
        choices = copy;
    }
    function text(order) {
        const choice = choices[order.id] || {action: "keep"};
        return choice.action === "move" ? "+" + choice.days + " d" : choice.action === "intake" ? "INTAKE" : choice.action === "drop" ? "DROP" : "TOMORROW";
    }
    // Carries the open orders over to tomorrow as chosen, and keeps the day's note.
    function close() {
        const list = open.map(order => Object.assign({id: order.id}, choices[order.id] || {action: "keep"}));
        Day.setDay({note: noteField.text}, undefined, () => {});
        if (list.length)
            Day.carryApply(list, tomorrow, (result, error) => report.closed(error));
        else
            closed(null);
    }
    function closed(error) {
        if (error) {
            ShellState.message(error.message, "error");
            return;
        }
        ShellState.message("Shift report filed", "success");
        load();
        changed();
    }
    function toggleStandDown() {
        Day.setDay({standDown: !(momentum && momentum.standDown)}, undefined, (result, error) => report.standDownSet(error));
    }
    function standDownSet(error) {
        if (error)
            ShellState.message(error.message, "error");
        Day.loadMomentum();
    }
    function cycle(order) {
        const choice = choices[order.id] || {action: "keep", days: 0};
        const order_ = ["keep", "move", "intake", "drop"];
        const next = order_[(order_.indexOf(choice.action) + 1) % order_.length];
        choose(order, next, next === "move" ? 2 : 0);
    }
    Component.onCompleted: load()
    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        ColumnLayout {
            width: report.width
            spacing: Theme.gapM
            RowLayout {
                Layout.fillWidth: true
                C.StationText {
                    text: "Shift report · " + Qt.formatDateTime(new Date(report.now), "ddd d MMM")
                    color: Theme.text
                    Layout.fillWidth: true
                }
                // A stand-down (a holiday, being ill) pauses days on target without breaking them.
                C.StationKey {
                    objectName: "standDown"
                    visible: !!report.momentum && !!report.momentum.enabled
                    text: report.momentum && report.momentum.standDown ? "End stand-down" : "Stand down today"
                    lit: !!report.momentum && !!report.momentum.standDown
                    Layout.fillWidth: false
                    implicitHeight: 26
                    implicitWidth: 130
                    onClicked: report.toggleStandDown()
                }
                C.StationKey {
                    text: "File report"
                    lit: true
                    Layout.fillWidth: false
                    implicitHeight: 26
                    implicitWidth: 100
                    onClicked: report.close()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapL
                Repeater {
                    model: [{name: "Cleared", value: String(report.cleared.length)},
                            {name: "Still open", value: String(report.open.length)},
                            {name: "Recorded", value: report.recorded > 0 ? Math.round(report.recorded / 60) + " min" : "—"},
                            {name: "Quiet on orders", value: report.quietMinutes + " min"}].concat(report.momentum && report.momentum.enabled
                            ? [{name: "Target", value: report.momentum.cleared + "/" + report.momentum.target},
                               {name: "Days on target", value: String(report.momentum.daysOnTarget || 0)}] : [])
                    Column {
                        id: stat
                        required property var modelData
                        C.StationText {
                            text: stat.modelData.name
                        }
                        Text {
                            text: stat.modelData.value
                            font.family: Theme.instrument
                            font.pixelSize: Theme.heading - 4
                            color: Theme.text
                        }
                    }
                }
            }
            C.StationText {
                text: "Cleared today"
                visible: report.cleared.length > 0
            }
            Repeater {
                model: report.cleared
                C.Label {
                    required property var modelData
                    text: "● " + modelData.text
                    color: Theme.muted
                    font.pixelSize: Theme.label
                    Layout.fillWidth: true
                }
            }
            C.StationText {
                text: "Not cleared · click a choice to change it, then File report"
                visible: report.open.length > 0
            }
            Repeater {
                model: report.open
                Rectangle {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    height: 28
                    radius: 4
                    color: Theme.panel
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.gapS
                        anchors.rightMargin: Theme.gapS
                        C.Label {
                            Layout.fillWidth: true
                            text: row.modelData.text
                            font.pixelSize: Theme.label
                        }
                        C.StationKey {
                            text: report.text(row.modelData)
                            Layout.fillWidth: false
                            implicitHeight: 22
                            Accessible.name: "Carry over: " + text
                            onClicked: report.cycle(row.modelData)
                        }
                    }
                }
            }
            C.StationText {
                text: "Note for the day"
            }
            C.Field {
                id: noteField
                Layout.fillWidth: true
                implicitHeight: 32
                placeholderText: "One line"
                maximumLength: 500
                font.pixelSize: Theme.label
                Keys.onEscapePressed: event => event.accepted = false
            }
            C.StationText {
                text: "Cleared per day · last 4 weeks, by site"
                visible: report.momentum !== null
            }
            Row {
                visible: report.momentum !== null
                spacing: 3
                Repeater {
                    model: report.momentum && report.momentum.perDay ? report.momentum.perDay : []
                    Column {
                        id: column
                        required property var modelData
                        width: 14
                        Accessible.name: column.modelData.date + ": " + column.modelData.cleared + " cleared"
                        Item {
                            width: 14
                            height: 70
                            Column {
                                anchors.bottom: parent.bottom
                                width: 14
                                spacing: 0
                                Repeater {
                                    model: report.siteNames.filter(name => column.modelData.bySite[name])
                                    Rectangle {
                                        id: piece
                                        required property string modelData
                                        required property int index
                                        width: 14
                                        height: Math.max(2, column.modelData.bySite[piece.modelData] * 66 / report.peak)
                                        // Sites are told apart by shade, not only hue, so the column reads in grey too.
                                        color: Qt.hsla(Theme.accent.hslHue, 0.35, 0.35 + 0.12 * (report.siteNames.indexOf(piece.modelData) % 4), 1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            C.StationText {
                text: "Quiet minutes per day · last 4 weeks"
                visible: report.momentum !== null
            }
            Row {
                visible: report.momentum !== null
                spacing: 3
                Repeater {
                    model: report.momentum && report.momentum.perDay ? report.momentum.perDay : []
                    Item {
                        id: quiet
                        required property var modelData
                        width: 14
                        height: 50
                        Accessible.name: quiet.modelData.date + ": " + quiet.modelData.quietMinutes + " minutes of Quiet"
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: 14
                            height: quiet.modelData.quietMinutes > 0 ? Math.max(2, quiet.modelData.quietMinutes * 46 / report.quietPeak) : 0
                            color: Theme.accent
                            opacity: 0.6
                        }
                    }
                }
            }
        }
    }
}
