import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

BarKey {
    id: clockKey
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property bool seconds: ShellState.setting("clockSeconds", false)
    readonly property string style: ShellState.setting("clockFormat", "date-time")
    readonly property string time: Qt.formatDateTime(bar.now, ShellState.setting("clock24h", true) ? (seconds ? "HH:mm:ss" : "HH:mm") : (seconds ? "h:mm:ss AP" : "h:mm AP"))
    readonly property string day: style === "time" ? "" : Qt.formatDateTime(bar.now, style === "date-time" ? "ddd d MMM" : "ddd")
    readonly property string temperature: bar.weather && bar.weather.current && bar.weather.current.temperature !== null && bar.weather.current.temperature !== undefined ? bar.weather.current.temperature + "°" : ""
    // In the middle zone it gives up the weather, then the date, before crowding the sides.
    readonly property real room: parent && parent.zone === "center" ? bar.centerRoom : Infinity
    readonly property real timeWidth: Math.ceil(timeMetrics.advanceWidth) + leftPadding + rightPadding
    readonly property real dayWidth: day !== "" ? Math.ceil(dayMetrics.advanceWidth) + 10 : 0
    readonly property bool showDay: day !== "" && timeWidth + dayWidth <= room
    readonly property bool showWeather: temperature !== "" && (day === "" || showDay) && timeWidth + dayWidth + Math.ceil(weatherMetrics.advanceWidth) + 26 <= room
    TextMetrics {
        id: timeMetrics
        text: clockKey.time
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: 650
        font.features: ({"tnum": 1})
    }
    TextMetrics {
        id: dayMetrics
        text: clockKey.day
        font.family: Theme.font
        font.pixelSize: 12
    }
    TextMetrics {
        id: weatherMetrics
        text: clockKey.temperature
        font.family: Theme.font
        font.pixelSize: 12
        font.features: ({"tnum": 1})
    }
    leftPadding: 12
    rightPadding: 12
    selected: ShellState.panel === "calendar" && ShellState.screenName === bar.outputName
    hint: Qt.formatDateTime(bar.now, "dddd, d MMMM yyyy") + (temperature ? "\n" + bar.weather.current.label + " · " + temperature : "")
    tooltip: bar.tooltip
    Accessible.name: "Clock and sky, " + Qt.formatDateTime(bar.now, "dddd d MMMM") + ", " + time
    onClicked: ShellState.toggle("calendar", bar.outputName)
    // Labels without eliding, so their implicit widths stay the full text.
    contentItem: RowLayout {
        spacing: 8
        C.Label {
            text: clockKey.time
            font.pixelSize: 13
            font.weight: 650
            font.features: ({"tnum": 1})
            elide: Text.ElideNone
        }
        C.Label {
            visible: clockKey.showDay
            text: clockKey.day
            color: Theme.textMuted
            font.pixelSize: 12
            elide: Text.ElideNone
        }
        RowLayout {
            visible: clockKey.showWeather
            spacing: Theme.gapXs
            C.Icon {
                name: bar.weather && bar.weather.current ? bar.weather.current.icon : "cloud"
                size: 13
                color: Theme.textMuted
            }
            C.Label {
                text: clockKey.temperature
                color: Theme.textMuted
                font.pixelSize: 12
                font.features: ({"tnum": 1})
                elide: Text.ElideNone
            }
        }
    }
}
