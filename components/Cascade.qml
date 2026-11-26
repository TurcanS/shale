import QtQuick
import "../core"

// An item that arrives in turn as its panel opens: "transform: C.Cascade { id: arrive; panel: "clipboard"; order:
// index }" with "opacity: arrive.shown". When PanelHost starts the panel's entrance (Motion.entering), the item
// waits its turn (order × the level's stagger, after the entrance's own delay), then comes in from (dx, dy) and
// seats. Items opened later, and Calm or Reduce motion, simply stand there.
Translate {
    id: root
    property string panel: ""
    property int order: 0
    // Items past this come with the last one, so a long list doesn't keep arriving.
    property int limit: 10
    // Where the item starts, in pixels at Lively (Playful goes further).
    property real dx: 0
    property real dy: -12
    property real overshoot: 0.8
    property int duration: 300
    // A share of the stagger between items: more for big ones, less for rows.
    property real spacing: 1
    property real progress: 1
    readonly property real shown: Math.min(1, progress * 3)
    x: dx * Motion.travel * (1 - progress)
    y: dy * Motion.travel * (1 - progress)
    function play(delay) {
        if (Motion.calm)
            return;
        run.stop();
        progress = 0;
        wait.duration = Math.max(1, Motion.ms(delay) + Math.min(order, limit) * Motion.ms(Motion.stagger * spacing));
        run.start();
    }
    property Connections link: Connections {
        target: Motion
        function onEntering(panel, delay) {
            if (panel === root.panel)
                root.play(delay);
        }
    }
    property SequentialAnimation run: SequentialAnimation {
        PauseAnimation {
            id: wait
            duration: 1
        }
        NumberAnimation {
            target: root
            property: "progress"
            from: 0
            to: 1
            duration: Motion.ms(root.duration)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.seatCurve(Motion.ov(root.overshoot))
        }
    }
}
