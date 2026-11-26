import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Clock and sky: the month, the picked day, and the weather with the sun's path.
FocusScope {
    id: root
    readonly property string title: Qt.formatDateTime(today, "dddd d")
    readonly property string headerNote: Qt.formatDateTime(today, "MMMM yyyy") + " · week " + week(today)
    readonly property int titleSize: 22
    readonly property int panelWidth: 440
    // Grows past the design height only while the weather search lists cities.
    readonly property int panelHeight: Math.ceil(body.implicitHeight) + Theme.casePadding * 2 + 42
    property date today: new Date()
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)
    // The day the agenda shows; clicking a day picks it.
    property date picked: today
    readonly property int firstDay: ShellState.firstDayOfWeek
    readonly property int offset: (month.getDay() - firstDay + 7) % 7
    readonly property bool pickedToday: sameDay(picked, today)
    property alias weatherCard: weatherCard
    function shift(delta) {
        month = new Date(month.getFullYear(), month.getMonth() + delta, 1);
    }
    // A new month turns over like a desk calendar's page: forward hinges on its top edge, back on its bottom.
    property date shownMonth: month
    property int turnDirection: 1
    property real turn: 1
    onMonthChanged: {
        if (month.getTime() !== shownMonth.getTime() && !Motion.calm) {
            turnDirection = month > shownMonth ? 1 : -1;
            turning.restart();
        }
        shownMonth = month;
    }
    NumberAnimation {
        id: turning
        target: root
        property: "turn"
        from: 0
        to: 1
        duration: Motion.ms(340)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.seatCurve(Motion.ov(0.9))
    }
    // The month grid is one Tab stop: the picked day, or the first of the month when the picked day is elsewhere.
    readonly property date tabDay: picked.getFullYear() === month.getFullYear() && picked.getMonth() === month.getMonth() ? picked : month
    // Arrow keys in the grid pick the day next to the focused one (a week up or down), into the next month when they
    // cross one.
    function moveDay(from, days) {
        const day = new Date(from.getFullYear(), from.getMonth(), from.getDate() + days);
        if (day.getFullYear() !== month.getFullYear() || day.getMonth() !== month.getMonth())
            month = new Date(day.getFullYear(), day.getMonth(), 1);
        picked = day;
        Qt.callLater(() => {
            const cell = dayCells.itemAt(day.getDate() - 1 + root.offset);
            if (cell)
                cell.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    function goToday() {
        month = new Date(today.getFullYear(), today.getMonth(), 1);
        picked = today;
    }
    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    // ISO 8601 week number.
    function week(date) {
        const day = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        day.setUTCDate(day.getUTCDate() + 4 - (day.getUTCDay() || 7));
        const start = new Date(Date.UTC(day.getUTCFullYear(), 0, 1));
        return Math.ceil(((day - start) / 86400000 + 1) / 7);
    }
    function dayOfYear(date) {
        return Math.round((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - new Date(date.getFullYear(), 0, 1)) / 86400000) + 1;
    }
    // "In 3 days", "Yesterday", … from today to the picked day.
    function distance(date) {
        const days = Math.round((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - new Date(today.getFullYear(), today.getMonth(), today.getDate())) / 86400000);
        if (days === 1)
            return "Tomorrow";
        if (days === -1)
            return "Yesterday";
        return days > 0 ? "In " + days + " days" : -days + " days ago";
    }
    function copy(text, note) {
        ShellState.run("clipboard.write", {text: text}, () => ShellState.message(note, "success"));
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            const was = root.pickedToday;
            root.today = new Date();
            // Past midnight the agenda follows today unless another day was picked.
            if (was)
                root.picked = root.today;
        }
    }
    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: 10
        // Month: title, Today and ‹ ›, the weekdays, then six weeks.
        C.Card {
            Layout.fillWidth: true
            implicitHeight: monthColumn.implicitHeight + 24
            WheelHandler {
                property double lastShift: 0
                onWheel: event => {
                    if (event.angleDelta.y === 0 || Date.now() - lastShift < 180)
                        return;
                    lastShift = Date.now();
                    root.shift(event.angleDelta.y < 0 ? 1 : -1);
                }
            }
            ColumnLayout {
                id: monthColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    C.Label {
                        text: Qt.formatDateTime(root.month, "MMMM yyyy")
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    C.Button {
                        text: "Today"
                        implicitHeight: 26
                        leftPadding: 10
                        rightPadding: 10
                        labelSize: 12
                        cornerRadius: 8
                        hint: "Go to today · Home"
                        onClicked: root.goToday()
                    }
                    C.Button {
                        glyph: "back"
                        implicitWidth: 26
                        implicitHeight: 26
                        padding: 7
                        cornerRadius: 8
                        hint: "Previous month · Page Up"
                        onClicked: root.shift(-1)
                    }
                    C.Button {
                        glyph: "chevron"
                        implicitWidth: 26
                        implicitHeight: 26
                        padding: 7
                        cornerRadius: 8
                        hint: "Next month · Page Down"
                        onClicked: root.shift(1)
                    }
                }
                GridLayout {
                    id: monthPage
                    columns: 7
                    columnSpacing: 0
                    rowSpacing: 2
                    Layout.fillWidth: true
                    opacity: Math.min(1, root.turn * 2.5)
                    transform: Rotation {
                        origin.x: monthPage.width / 2
                        origin.y: root.turnDirection > 0 ? 0 : monthPage.height
                        axis { x: 1; y: 0; z: 0 }
                        angle: root.turn < 1 ? root.turnDirection * 80 * (1 - root.turn) : 0
                    }
                    Repeater {
                        model: 7
                        C.Label {
                            required property int index
                            // Two letters, as in "Mo Tu We".
                            text: Qt.locale().dayName(((root.firstDay + index) % 7) || 7, Locale.ShortFormat).replace(/\.$/, "").slice(0, 2)
                            color: Theme.textDim
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 18
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    Repeater {
                        id: dayCells
                        model: 42
                        // One day: today filled with the accent, the picked day ringed, other months dim.
                        C.Button {
                            id: cell
                            required property int index
                            readonly property date day: new Date(root.month.getFullYear(), root.month.getMonth(), 1 + index - root.offset)
                            readonly property bool outside: day.getMonth() !== root.month.getMonth()
                            readonly property bool isToday: root.sameDay(day, root.today)
                            readonly property bool isPicked: !isToday && root.sameDay(day, root.picked)
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitWidth: 30
                            implicitHeight: 30
                            padding: 0
                            text: String(day.getDate())
                            hint: Qt.formatDateTime(day, "dddd, d MMMM yyyy")
                            Accessible.name: (outside ? "Go to " : "Show ") + hint
                            focusPolicy: activeFocus || root.sameDay(day, root.tabDay) ? Qt.StrongFocus : Qt.ClickFocus
                            Keys.onLeftPressed: root.moveDay(day, -1)
                            Keys.onRightPressed: root.moveDay(day, 1)
                            Keys.onUpPressed: root.moveDay(day, -7)
                            Keys.onDownPressed: root.moveDay(day, 7)
                            // Days from a neighbouring month go there; days in view are picked for the agenda.
                            onClicked: {
                                if (outside)
                                    root.month = new Date(day.getFullYear(), day.getMonth(), 1);
                                root.picked = day;
                            }
                            background: Item {
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    radius: 9
                                    color: cell.isToday ? Theme.accent : cell.isPicked ? Theme.keySelected : cell.hovered || cell.down ? cell.wash : "transparent"
                                    border.width: cell.isPicked ? 1 : 0
                                    border.color: Theme.accentLine
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Theme.fast
                                        }
                                    }
                                }
                            }
                            contentItem: C.Label {
                                text: cell.text
                                color: cell.isToday ? Theme.accentInk : cell.outside ? Theme.mix(Theme.module, Theme.textDim, 0.4) : Theme.text
                                font.pixelSize: 13
                                font.weight: cell.isToday ? Font.Bold : Font.Medium
                                font.features: ({"tnum": 1})
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
        // The picked day. Shale reads no calendars yet, so this says where the day sits and offers to copy it.
        C.Card {
            Layout.fillWidth: true
            implicitHeight: agendaColumn.implicitHeight + 24
            ColumnLayout {
                id: agendaColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    C.Label {
                        text: root.pickedToday ? "Today" : Qt.formatDateTime(root.picked, "dddd d MMMM")
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    C.Button {
                        text: "Copy date"
                        glyph: "copy"
                        flat: true
                        implicitHeight: 26
                        leftPadding: 8
                        rightPadding: 8
                        labelSize: 12
                        cornerRadius: 8
                        Accessible.name: "Copy " + Qt.formatDateTime(root.picked, "dddd, d MMMM yyyy")
                        onClicked: root.copy(Qt.formatDateTime(root.picked, "yyyy-MM-dd"), "Date copied · " + Qt.formatDateTime(root.picked, "yyyy-MM-dd"))
                    }
                    C.Button {
                        visible: root.pickedToday
                        text: "Copy time"
                        flat: true
                        implicitHeight: 26
                        leftPadding: 8
                        rightPadding: 8
                        labelSize: 12
                        cornerRadius: 8
                        Accessible.name: "Copy current time"
                        onClicked: root.copy(Qt.formatDateTime(new Date(), ShellState.timeFormat), "Time copied")
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 3
                        Layout.fillHeight: true
                        radius: 2
                        color: root.pickedToday ? Theme.accent : Theme.textDim
                    }
                    C.Label {
                        text: root.pickedToday ? Qt.formatDateTime(root.today, ShellState.timeFormat) : Qt.formatDateTime(root.picked, "ddd")
                        color: Theme.textSecondary
                        font.pixelSize: 13
                        font.features: ({"tnum": 1})
                        Layout.preferredWidth: 44
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        C.Label {
                            text: root.pickedToday ? "Week " + root.week(root.today) + " · day " + root.dayOfYear(root.today) : root.distance(root.picked)
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        C.Label {
                            text: root.pickedToday ? Qt.formatDateTime(root.today, "d MMMM yyyy") : "Week " + root.week(root.picked) + " · " + Qt.formatDateTime(root.picked, "d MMMM yyyy")
                            color: Theme.textDim
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
        WeatherCard {
            id: weatherCard
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: implicitHeight
        }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            shift(event.key === Qt.Key_PageUp ? -1 : 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            goToday();
            event.accepted = true;
        }
    }
    Keys.onLeftPressed: shift(-1)
    Keys.onRightPressed: shift(1)
}
