import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

BarStatusPart {
    id: batteryButton
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property bool low: !Services.batteryCharging && Services.onBattery && Services.batteryPercent <= 20
    // Low charge always shows its number, even when the percentage is turned off.
    readonly property bool percent: {
        const choice = ShellState.setting("batteryPercent", "auto");
        return low || choice === "always" || (choice === "auto" && !bar.compact);
    }
    readonly property color level: tone === "danger" ? Theme.danger : tone === "warning" ? Theme.warning : Theme.text
    shown: Services.batteryAvailable
    text: percent ? Math.round(Services.batteryPercent) + "%" : ""
    tone: !low ? "" : Services.batteryPercent <= 10 ? "danger" : "warning"
    hint: "Battery " + Math.round(Services.batteryPercent) + "% · Power profiles"
    tooltip: bar.tooltip
    Accessible.name: "Battery " + Math.round(Services.batteryPercent) + "%" + (Services.batteryCharging ? ", charging" : "")
    selected: bar.controlActive("power")
    // Plugged in: the key flashes once, like a charge lamp coming on.
    readonly property bool charging: Services.batteryCharging
    onChargingChanged: if (charging) lamp.flash()
    C.WarmUp {
        id: lamp
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        radius: Theme.radiusSegment
        color: Theme.accent
        peak: 0.35
    }
    onClicked: bar.toggleControl("power")
    contentItem: RowLayout {
        spacing: 5
        C.Icon {
            visible: Services.batteryCharging
            name: "bolt"
            size: 12
            color: batteryButton.foreground
        }
        // A small battery that empties with the charge.
        Rectangle {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 10
            radius: 3
            color: "transparent"
            border.width: 1.5
            border.color: batteryButton.low ? batteryButton.level : Theme.textSecondary
            Rectangle {
                x: 3
                y: 3
                width: Math.max(1, (parent.width - 6) * Math.min(1, Services.batteryPercent / 100))
                height: parent.height - 6
                radius: 1
                color: batteryButton.level
            }
        }
        C.Label {
            visible: batteryButton.text !== ""
            text: batteryButton.text
            color: batteryButton.foreground
            font.pixelSize: 12
            font.features: ({"tnum": 1})
            elide: Text.ElideNone
        }
    }
}
