import QtQuick
import "../core"
import "../components" as C

// Something live or on (listening, recording, a focus session): a round raised key with an accent glyph.
BarKey {
    id: chip
    // Coming on, it warms up like an indicator lamp.
    function flash() {
        lamp.flash();
    }
    onShownChanged: if (shown) lamp.flash()
    implicitHeight: 24
    cornerRadius: 12
    rest: Theme.raised
    raisedKey: true
    leftPadding: 10
    rightPadding: 10
    foreground: Theme.text
    glyphColor: Theme.accentText
    C.WarmUp {
        id: lamp
        anchors.fill: parent
        radius: chip.cornerRadius
        color: Theme.accent
        peak: 0.35
    }
}
