import QtQuick
import "../core"

// An indicator lamp coming on: lay it over something that lights up (a tile turning on, a badge, a status dot) and
// call flash(). It glows brighter than at rest for a moment, then settles. Nothing under Calm or Reduce motion.
Rectangle {
    id: root
    // The brightest the glow gets, as an opacity of the colour.
    property real peak: 0.32
    color: Theme.knob
    opacity: 0
    visible: opacity > 0
    function flash() {
        if (Motion.calm)
            return;
        glow.restart();
    }
    SequentialAnimation {
        id: glow
        NumberAnimation {
            target: root
            property: "opacity"
            from: 0
            to: root.peak * (1 + 0.5 * Motion.glow)
            duration: Motion.ms(70)
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: 0
            duration: Motion.ms(300)
            easing.type: Easing.InOutQuad
        }
    }
}
