import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C
import "../core/format.js" as Format

// The glance chips under the clock: today's weather, the battery and how many notifications wait. Only counts are
// shown for notifications; their contents stay private. Nothing here can be pressed.
RowLayout {
    id: root
    spacing: 8
    visible: items.length > 0

    // The forecast Clock and sky shows, as the bar reads it (the backend keeps it for 30 minutes). Nothing is
    // requested until a city is chosen there.
    readonly property var weather: Weather.forecast

    readonly property var items: {
        const list = [];
        const current = weather && weather.current;
        if (current && current.temperature !== null && current.temperature !== undefined) {
            const label = String(current.label || "");
            list.push({glyph: current.icon || "cloud", text: current.temperature + "°" + (label ? " " + label.charAt(0).toLowerCase() + label.slice(1) : "")});
        }
        if (Services.batteryAvailable) {
            const seconds = Services.batterySeconds;
            const span = Format.shortSpan(seconds);
            list.push({glyph: Services.batteryCharging ? "bolt" : "battery",
                       text: Math.round(Services.batteryPercent) + "%" + (Services.batteryCharging ? (span ? " · full in " + span : " · charging") : span ? " · " + span + " left" : ""),
                       tone: !Services.batteryCharging && Services.batteryPercent <= 15 ? "danger" : ""});
        }
        const count = Services.notificationModel.count;
        if (count > 0)
            list.push({glyph: "bell", text: (count > 99 ? "99+" : String(count)) + (count === 1 ? " notification" : " notifications")});
        return list;
    }

    Repeater {
        model: root.items
        delegate: Rectangle {
            id: chip
            required property var modelData
            implicitWidth: chipRow.implicitWidth + 28
            implicitHeight: 36
            radius: height / 2
            color: Theme.tint(Theme.caseColor, 0.55)
            border.width: 1
            border.color: Theme.edge
            Accessible.role: Accessible.StaticText
            Accessible.name: chip.modelData.text
            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 8
                C.Icon {
                    name: chip.modelData.glyph
                    size: 15
                    color: chip.modelData.tone === "danger" ? Theme.dangerText : Theme.textSecondary
                }
                C.Label {
                    text: chip.modelData.text
                    font.pixelSize: 14
                    font.features: {"tnum": 1}
                    elide: Text.ElideNone
                    color: chip.modelData.tone === "danger" ? Theme.dangerText : Theme.text
                }
            }
        }
    }
}
