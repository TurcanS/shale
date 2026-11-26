import QtQuick
import "../core"

// "C.Ballistic on value {}": a VU needle. It rises fast and swings a little past a higher value, and falls back
// slower, so a level reads as a meter rather than a bar being resized. Calm rises and falls the same, without the
// swing; Reduce motion jumps.
Behavior {
    id: root
    enabled: !Motion.reduced
    // Under the needle: true while it has to climb to the new value.
    readonly property bool rising: targetProperty.object && targetValue > targetProperty.object[targetProperty.name]
    SpringAnimation {
        spring: Motion.calm ? 3.4 : root.rising ? (Motion.playful ? 6 : 5) : 2.4
        damping: Motion.calm ? 0.55 : root.rising ? (Motion.playful ? 0.24 : 0.32) : 0.36
        epsilon: 0.002
    }
}
