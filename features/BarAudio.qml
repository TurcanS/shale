import QtQuick
import "../services"

BarStatusPart {
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    glyph: Services.muted ? "mute" : "volume"
    selected: bar.controlActive("audio")
    hint: "Audio · " + Math.round(Services.volume * 100) + "%"
    tooltip: bar.tooltip
    onClicked: bar.toggleControl("audio")
    WheelHandler {
        property real travelled: 0
        onWheel: event => {
            travelled += event.angleDelta.y;
            const steps = Math.trunc(travelled / 120);
            if (!Services.audioAvailable || !steps)
                return;
            travelled -= steps * 120;
            Services.setVolume(Services.volume + 0.05 * steps);
        }
    }
    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: Services.toggleMute()
    }
}
