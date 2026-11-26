import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

BarLiveChip {
    id: privacyButton
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property bool mic: Services.micUsers.length > 0
    readonly property bool camera: bar.cameraUsers.length > 0
    readonly property bool sharing: Services.screenSharers.length > 0
    readonly property var apps: Services.micUsers.concat(bar.cameraUsers, Services.screenSharers).filter((name, i, all) => all.indexOf(name) === i)
    shown: mic || camera || sharing
    hint: [mic ? "Microphone in use: " + Services.micUsers.join(", ") : "",
           camera ? "Camera in use: " + bar.cameraUsers.join(", ") : "",
           sharing ? "Sharing your screen with " + Services.screenSharers.join(", ") : ""].filter(line => line).join("\n")
    tooltip: bar.tooltip
    Accessible.name: hint
    onClicked: bar.toggleControl("audio")
    contentItem: RowLayout {
        spacing: 6
        C.Icon { visible: privacyButton.mic; name: "mic"; size: 12; color: Theme.accentText }
        C.Icon { visible: privacyButton.camera; name: "camera"; size: 12; color: Theme.accentText }
        C.Icon { visible: privacyButton.sharing; name: "cast"; size: 12; color: Theme.accentText }
        // Names the app; more than one shows as "+N".
        C.Label {
            visible: !bar.compact && privacyButton.apps.length > 0
            text: privacyButton.apps.length ? privacyButton.apps[0] + (privacyButton.apps.length > 1 ? " +" + (privacyButton.apps.length - 1) : "") : ""
            color: Theme.text
            font.pixelSize: 11
            font.weight: Font.DemiBold
            elide: Text.ElideNone
        }
    }
}
