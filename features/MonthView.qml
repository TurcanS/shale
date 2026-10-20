pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// The month grid of the calendar: the Calendar panel and the Day hub's drawer both show it. It does not keep the
// month itself; it asks its owner to move.
Rectangle {
    id: root
    required property date month
    required property date today
    readonly property int firstDay: ShellState.firstDayOfWeek
    readonly property int offset: (month.getDay() - firstDay + 7) % 7
    signal shiftRequested(int delta)
    signal monthChosen(date month)
    implicitHeight: calendarBody.implicitHeight + 24
    radius: Theme.controlRadius
    color: Theme.surface
    WheelHandler {
        property double lastShift: 0
        onWheel: event => {
            if (event.angleDelta.y === 0 || Date.now() - lastShift < 180)
                return;
            lastShift = Date.now();
            root.shiftRequested(event.angleDelta.y < 0 ? 1 : -1);
        }
    }
    ColumnLayout {
        id: calendarBody
        anchors.fill: parent
        anchors.margins: 12
        spacing: Theme.gapS
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Button {
                glyph: "back"
                implicitWidth: 36
                implicitHeight: 32
                flat: true
                hint: "Previous month"
                onClicked: root.shiftRequested(-1)
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
                onClicked: root.shiftRequested(1)
            }
        }
        GridLayout {
            columns: 7
            columnSpacing: 2
            rowSpacing: Theme.gapXs
            Layout.fillWidth: true
            Layout.fillHeight: true
            Repeater {
                model: 7
                C.Label {
                    id: dayName
                    required property int index
                    text: Qt.locale().dayName(((root.firstDay + dayName.index) % 7) || 7, Locale.ShortFormat)
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
                    id: cell
                    required property int index
                    readonly property date day: new Date(root.month.getFullYear(), root.month.getMonth(), 1 + cell.index - root.offset)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    implicitWidth: 30
                    implicitHeight: Math.max(30, Theme.body + 16)
                    cornerRadius: 8
                    text: String(cell.day.getDate())
                    flat: true
                    opacity: cell.day.getMonth() === root.month.getMonth() ? 1 : 0.64
                    selected: Qt.formatDateTime(cell.day, "yyyy-MM-dd") === Qt.formatDateTime(root.today, "yyyy-MM-dd")
                    accent: cell.selected
                    readonly property bool outside: cell.day.getMonth() !== root.month.getMonth()
                    hint: Qt.formatDateTime(cell.day, "dddd, d MMMM yyyy")
                    Accessible.name: (cell.outside ? "Go to " : "Copy ") + cell.hint
                    // Days from a neighbouring month navigate there; days in view copy the date.
                    onClicked: {
                        if (cell.outside) {
                            root.monthChosen(new Date(cell.day.getFullYear(), cell.day.getMonth(), 1));
                            return;
                        }
                        ShellState.run("clipboard.write", {
                            text: Qt.formatDateTime(cell.day, "yyyy-MM-dd")
                        }, () => ShellState.message("Date copied · " + Qt.formatDateTime(cell.day, "yyyy-MM-dd"), "success"));
                    }
                }
            }
        }
    }
}
