import QtQuick
import "../core"

// "transform: C.Shake { id: shake }" and shake.start(): a decaying side-to-side shake, for a wrong password or a
// value that can't go further. Under Calm it is smaller; Reduce motion keeps it still.
Translate {
    id: root
    // Widest swing in pixels, at the start.
    property real amplitude: 6
    property real phase: 1
    x: Motion.reduced ? 0 : root.amplitude * (Motion.calm ? 0.6 : 1) * Math.sin(root.phase * Math.PI * 7) * (1 - root.phase)
    function start() {
        if (!Motion.reduced)
            run.restart();
    }
    property NumberAnimation run: NumberAnimation {
        target: root
        property: "phase"
        from: 0
        to: 1
        duration: Motion.calm ? 280 : Motion.ms(420)
    }
}
