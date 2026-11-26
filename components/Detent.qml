import QtQuick
import "../core"

// "C.Detent on x {}": a selector clicking over. It holds for the first third of the way, snaps past the middle with a
// small overshoot and comes back to rest. Calm keeps the plain slide; Reduce motion is instant.
Behavior {
    id: root
    property real overshoot: 1
    property int duration: 240
    NumberAnimation {
        duration: Motion.reduced ? 0 : Motion.calm ? Theme.slide : Motion.ms(root.duration)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.calm ? Theme.easeOut : Motion.detentCurve(Motion.ov(root.overshoot))
    }
}
