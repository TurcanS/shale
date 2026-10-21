pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../core/day.js" as DayText
import "../services"
import "../components" as C

// The shift start, inside the hub: carry over yesterday's uncleared orders, look at today and pull orders in, set the
// target. Shown once a day (Day.shiftDue); every screen can be skipped, and so can the lot (Escape).
FocusScope {
    id: shift
    property real now: Date.now()
    // 0 carry over, 1 today, 2 target.
    property int screen: 0
    property var carry: []
    // Order id to choice: {action, days}. Every carried order starts as "keep".
    property var choices: ({})
    property int cursor: 0
    property int target: ShellState.setting("dailyTarget", 5)
    signal finished()
    readonly property var intake: Day.orders.filter(order => !order.doneAt && !order.parentId && (order.siteId === null || order.siteId === undefined)
                                                    && (order.dueAt === null || order.dueAt === undefined || order.dueAt >= dayEnd))
    readonly property real dayStart: new Date(new Date(now).getFullYear(), new Date(now).getMonth(), new Date(now).getDate()).getTime()
    readonly property real dayEnd: new Date(new Date(now).getFullYear(), new Date(now).getMonth(), new Date(now).getDate() + 1).getTime()
    readonly property var dueToday: Day.orders.filter(order => !order.doneAt && order.dueAt >= dayStart && order.dueAt < dayEnd)
    readonly property var rows: screen === 0 ? carry : screen === 1 ? intake : []
    readonly property var last7: Day.momentum ? Day.momentum.last7 : []
    readonly property string phrase: ["Carry over", "Today", "Target"][screen]

    function begin() {
        now = Date.now();
        screen = 0;
        cursor = 0;
        choices = ({});
        target = ShellState.setting("dailyTarget", 5);
        Day.logbook = true;
        // Marked as soon as it shows, so it appears exactly once a day however it ends.
        Day.startShift(null);
        Day.autoCarry();
        Day.carryList((result, error) => shift.listed(result, error));
        forceActiveFocus();
    }
    function listed(result, error) {
        carry = error ? [] : result;
        const kept = {};
        carry.forEach(order => kept[order.id] = {action: "keep", days: 0});
        choices = kept;
        // Nothing to carry: the first screen is skipped.
        if (!carry.length)
            screen = 1;
    }
    function choose(action, days) {
        const order = rows[cursor];
        if (screen !== 0 || !order)
            return;
        const copy = Object.assign({}, choices);
        copy[order.id] = {action: action, days: days || 0};
        choices = copy;
        if (cursor < rows.length - 1)
            cursor++;
    }
    function label(order) {
        const choice = choices[order.id] || {action: "keep"};
        return choice.action === "move" ? "+" + choice.days + " d" : choice.action === "intake" ? "INTAKE" : choice.action === "drop" ? "DROP" : "KEEP";
    }
    function next() {
        if (screen === 0 && carry.length) {
            const list = carry.map(order => Object.assign({id: order.id}, choices[order.id] || {action: "keep"}));
            Day.carryApply(list, Day.today(), (result, error) => shift.advance(error));
            return;
        }
        advance(null);
    }
    function advance(error) {
        if (error) {
            ShellState.message(error.message, "error");
            return;
        }
        cursor = 0;
        if (screen < 2)
            screen++;
        else
            done(true);
    }
    // Pull the selected Intake order into today.
    function pull() {
        const order = rows[cursor];
        if (screen === 1 && order)
            Day.update(order.id, {dueAt: dayStart, allDay: true});
    }
    function done(keepTarget) {
        Day.startShift(keepTarget ? target : null);
        Day.logbook = false;
        finished();
    }
    function skip() {
        if (screen < 2)
            advance(null);
        else
            done(false);
    }
    Keys.onPressed: event => {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) {
            done(false);
        } else if (event.key === Qt.Key_Up) {
            cursor = Math.max(0, cursor - 1);
        } else if (event.key === Qt.Key_Down) {
            cursor = Math.min(Math.max(0, rows.length - 1), cursor + 1);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            next();
        } else if (event.key === Qt.Key_S) {
            skip();
        } else if (screen === 0 && event.key === Qt.Key_K) {
            choose("keep");
        } else if (screen === 0 && event.key === Qt.Key_I) {
            choose("intake");
        } else if (screen === 0 && event.key === Qt.Key_D) {
            choose("drop");
        } else if (screen === 0 && event.key >= Qt.Key_1 && event.key <= Qt.Key_7) {
            choose("move", event.key - Qt.Key_0);
        } else if (screen === 1 && event.key === Qt.Key_P) {
            pull();
        } else if (screen === 2 && (event.key === Qt.Key_Right || event.key === Qt.Key_Plus || event.key === Qt.Key_Up)) {
            target = Math.min(100, target + 1);
        } else if (screen === 2 && (event.key === Qt.Key_Left || event.key === Qt.Key_Minus || event.key === Qt.Key_Down)) {
            target = Math.max(1, target - 1);
        } else {
            event.accepted = false;
        }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapM
        spacing: Theme.gapS
        RowLayout {
            Layout.fillWidth: true
            C.StationText {
                text: "Shift start · " + (shift.screen + 1) + " of 3 · " + shift.phrase
                color: Theme.text
                Layout.fillWidth: true
            }
            C.StationKey {
                text: "Skip · S"
                Layout.fillWidth: false
                implicitHeight: 26
                onClicked: shift.skip()
            }
            C.StationKey {
                text: shift.screen === 2 ? "Start shift · Enter" : "Next · Enter"
                lit: true
                Layout.fillWidth: false
                implicitHeight: 26
                onClicked: shift.next()
            }
        }
        C.Label {
            visible: shift.screen === 0
            text: shift.carry.length ? "Yesterday's orders still open. K keep for today · 1-7 move that many days · I back to Intake · D drop" : "Nothing was left over."
            color: Theme.muted
            font.pixelSize: Theme.small
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        C.Label {
            visible: shift.screen === 1
            text: "Due today: " + shift.dueToday.length + ". From Intake, P pulls the selected order into today."
            color: Theme.muted
            font.pixelSize: Theme.small
            Layout.fillWidth: true
        }
        ListView {
            visible: shift.screen < 2
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 1
            model: shift.rows
            delegate: Rectangle {
                id: slot
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 28
                radius: 4
                color: slot.index === shift.cursor ? Theme.selection : "transparent"
                Accessible.name: slot.modelData.text
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.gapS
                    anchors.rightMargin: Theme.gapS
                    C.Label {
                        Layout.fillWidth: true
                        text: slot.modelData.text
                        font.pixelSize: Theme.label
                    }
                    C.Label {
                        visible: slot.modelData.dueAt !== null && slot.modelData.dueAt !== undefined
                        text: DayText.dayLabel(slot.modelData.dueAt || 0, shift.now)
                        color: Theme.muted
                        font.pixelSize: Theme.small
                    }
                    C.StationText {
                        visible: shift.screen === 0
                        text: shift.label(slot.modelData)
                        color: Theme.accent
                    }
                }
                TapHandler {
                    onTapped: shift.cursor = slot.index
                }
            }
        }
        ColumnLayout {
            visible: shift.screen === 2
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.gapM
            C.Label {
                text: "How many orders to clear today?"
                color: Theme.muted
            }
            RowLayout {
                spacing: Theme.gapM
                C.StationKey {
                    text: "−"
                    Layout.fillWidth: false
                    implicitWidth: 40
                    Accessible.name: "Fewer"
                    onClicked: shift.target = Math.max(1, shift.target - 1)
                }
                Text {
                    text: shift.target
                    font.family: Theme.readout
                    font.pixelSize: 48
                    color: Theme.accent
                    Accessible.name: "Target " + shift.target
                }
                C.StationKey {
                    text: "+"
                    Layout.fillWidth: false
                    implicitWidth: 40
                    Accessible.name: "More"
                    onClicked: shift.target = Math.min(100, shift.target + 1)
                }
            }
            C.StationText {
                text: "Last 7 days"
            }
            Row {
                spacing: Theme.gapS
                Repeater {
                    model: shift.last7
                    Column {
                        id: day
                        required property int modelData
                        spacing: 2
                        Rectangle {
                            width: 28
                            height: Math.max(2, Math.min(60, day.modelData * 60 / Math.max(1, shift.target * 1.5)))
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: day.modelData >= shift.target ? Theme.accent : Theme.border
                        }
                        C.Label {
                            text: day.modelData
                            font.family: Theme.instrument
                            font.pixelSize: Theme.small
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
            Item {
                Layout.fillHeight: true
            }
        }
    }
}
