import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

FocusScope {
    id: root
    readonly property string title: "Calendar"
    readonly property int panelWidth: 360
    readonly property int panelHeight: 460 + extraHeight
    property date today: new Date()
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)
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
        spacing: Theme.gapL
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapL
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
        MonthView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            month: root.month
            today: root.today
            onShiftRequested: delta => root.shift(delta)
            onMonthChosen: month => root.month = month
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapS
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
