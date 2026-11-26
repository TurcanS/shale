import QtQuick
import "../core"

// "C.Seat on y {}": a module pushed home in its rail. It runs a little past the new value, comes back under it and
// settles. Calm keeps the plain Rack ease; Reduce motion is instant.
Behavior {
    id: root
    // How far past home, as a share of the level's overshoot.
    property real overshoot: 1
    property int duration: 300
    NumberAnimation {
        duration: Motion.reduced ? 0 : Motion.calm ? Theme.slide : Motion.ms(root.duration)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.calm ? Theme.easeOut : Motion.seatCurve(Motion.ov(root.overshoot))
    }
}
