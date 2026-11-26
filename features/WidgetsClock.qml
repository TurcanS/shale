import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// The Clock card: the date, the time at 64 px and how much of the day has gone. Opens Clock and sky.
WidgetsCard {
    id: root
    property date now: new Date()
    readonly property bool hours24: ShellState.setting("clock24h", true)
    readonly property real dayDone: (now.getHours() * 60 + now.getMinutes()) / 1440
    panel: "calendar"
    padding: 18
    // ISO 8601 week number, as Clock and sky counts weeks.
    function week(date) {
        const day = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        day.setUTCDate(day.getUTCDate() + 4 - (day.getUTCDay() || 7));
        const start = new Date(Date.UTC(day.getUTCFullYear(), 0, 1));
        return Math.ceil(((day - start) / 86400000 + 1) / 7);
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: Qt.formatDateTime(now, "dddd d MMMM, " + ShellState.timeFormat)
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        C.Label {
            text: Qt.formatDate(root.now, "dddd d MMMM")
            color: Theme.textMuted
            font.pixelSize: 14
            Layout.fillWidth: true
        }
        RowLayout {
            spacing: 6
            Layout.fillWidth: true
            C.Label {
                text: Qt.formatTime(root.now, root.hours24 ? "HH:mm" : "h:mm")
                font.pixelSize: 64
                font.weight: Font.DemiBold
                font.letterSpacing: -1.9
                font.features: ({"tnum": 1})
                lineHeight: 1.05
                elide: Text.ElideNone
            }
            C.Label {
                visible: !root.hours24
                text: Qt.formatTime(root.now, "AP")
                color: Theme.textDim
                font.pixelSize: 18
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: 12
            }
        }
        Item {
            Layout.fillHeight: true
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4
            radius: 2
            color: Theme.key
            Rectangle {
                width: parent.width * root.dayDone
                height: parent.height
                radius: 2
                color: Theme.accent
            }
        }
        C.Label {
            text: Math.round(root.dayDone * 100) + "% of the day gone · week " + root.week(root.now)
            color: Theme.textDim
            font.pixelSize: 11
            font.features: ({"tnum": 1})
            Layout.fillWidth: true
            Layout.topMargin: 6
        }
    }
}
