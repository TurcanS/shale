import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

FocusScope {
    id: root
    property date today: new Date()
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property int offset: (month.getDay() - firstDay + 7) % 7
    // The panel grows by the weather card so the month grid keeps its size.
    readonly property int extraHeight: weatherCard.implicitHeight + 16
    property alias weatherCard: weatherCard
    function shift(delta) {
        month = new Date(month.getFullYear(), month.getMonth() + delta, 1);
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.today = new Date()
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            C.Label {
                text: Qt.formatDateTime(root.today, "dd")
                font.pixelSize: 46
                font.family: Theme.mono
                font.weight: Font.Light
                Layout.preferredHeight: 52
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                C.Label {
                    text: Qt.formatDateTime(root.today, "dddd")
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                C.Label {
                    text: Qt.formatDateTime(root.today, "MMMM yyyy")
                    color: Theme.muted
                    font.pixelSize: Theme.small
                    Layout.fillWidth: true
                }
            }
            Rectangle {
                Layout.preferredWidth: 6
                Layout.preferredHeight: 24
                radius: 3
                color: Theme.accent
            }
        }
        WeatherCard {
            id: weatherCard
            Layout.fillWidth: true
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: calendarBody.implicitHeight + 24
            radius: Theme.controlRadius
            color: Theme.surface
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
                id: calendarBody
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    C.Button {
                        glyph: "back"
                        implicitWidth: 36
                        implicitHeight: 32
                        flat: true
                        hint: "Previous month"
                        onClicked: root.shift(-1)
                    }
                    C.Label {
                        text: Qt.formatDateTime(root.month, "MMMM yyyy")
                        font.pixelSize: Theme.body
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    C.Button {
                        glyph: "chevron"
                        implicitWidth: 36
                        implicitHeight: 32
                        flat: true
                        hint: "Next month"
                        onClicked: root.shift(1)
                    }
                }
                GridLayout {
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: 3
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Repeater {
                        model: 7
                        C.Label {
                            required property int index
                            text: Qt.locale().dayName(((root.firstDay + index) % 7) || 7, Locale.ShortFormat)
                            color: Theme.muted
                            font.pixelSize: Theme.caption
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    Repeater {
                        model: 42
                        C.Button {
                            required property int index
                            readonly property date day: new Date(root.month.getFullYear(), root.month.getMonth(), 1 + index - root.offset)
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            implicitWidth: 30
                            implicitHeight: Math.max(30, Theme.body + 16)
                            cornerRadius: 8
                            text: String(day.getDate())
                            flat: true
                            opacity: day.getMonth() === root.month.getMonth() ? 1 : 0.64
                            selected: Qt.formatDateTime(day, "yyyy-MM-dd") === Qt.formatDateTime(root.today, "yyyy-MM-dd")
                            accent: selected
                            readonly property bool outside: day.getMonth() !== root.month.getMonth()
                            hint: Qt.formatDateTime(day, "dddd, d MMMM yyyy")
                            Accessible.name: (outside ? "Go to " : "Copy ") + hint
                            // Days from a neighbouring month navigate there; days in view copy the date.
                            onClicked: {
                                if (outside) {
                                    root.month = new Date(day.getFullYear(), day.getMonth(), 1);
                                    return;
                                }
                                ShellState.run("clipboard.write", {
                                    text: Qt.formatDateTime(day, "yyyy-MM-dd")
                                }, () => ShellState.message("Date copied · " + Qt.formatDateTime(day, "yyyy-MM-dd"), "success"));
                            }
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            C.Button {
                text: "Today"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                glyph: "calendar"
                enabled: root.month.getFullYear() !== root.today.getFullYear() || root.month.getMonth() !== root.today.getMonth()
                onClicked: root.month = new Date(root.today.getFullYear(), root.today.getMonth(), 1)
            }
            C.Button {
                text: "Copy " + Qt.formatDateTime(root.today, ShellState.timeFormat)
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                glyph: "copy"
                Accessible.name: "Copy current time"
                onClicked: ShellState.run("clipboard.write", {
                    text: Qt.formatDateTime(new Date(), ShellState.timeFormat)
                }, () => ShellState.message("Time copied", "success"))
            }
        }
        C.Label {
            text: "Local time · " + Qt.formatDateTime(root.today, "t")
            color: Theme.disabled
            font.pixelSize: Theme.caption
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            shift(event.key === Qt.Key_PageUp ? -1 : 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            month = new Date(today.getFullYear(), today.getMonth(), 1);
            event.accepted = true;
        }
    }
    Keys.onLeftPressed: shift(-1)
    Keys.onRightPressed: shift(1)
}
