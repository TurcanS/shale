import QtQuick
import "../core"

BarStatusPart {
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property var network: (ShellState.wifi.networks || []).find(n => n.connected) || null
    readonly property bool connected: ShellState.wifi.state === "connected"
    shown: bar.width >= 560 && ShellState.wifiAvailable
    // The arcs show the signal; dimmed while disconnected so a dropped network is visible at a glance.
    glyph: !connected ? (ShellState.wifi.powered ? "wifi" : "wifi-off") : !network || network.signal >= 67 ? "wifi" : network.signal >= 34 ? "wifi-2" : "wifi-1"
    opacity: connected || bar.controlActive("wifi") ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    hint: connected ? "Wi-Fi" + (network ? " · " + network.name : "") : ShellState.wifi.powered ? "Wi-Fi · Not connected" : "Wi-Fi · Off"
    tooltip: bar.tooltip
    selected: bar.controlActive("wifi")
    onClicked: bar.toggleControl("wifi")
}
