import QtQuick
import QtQuick.Shapes
import "../core"

// A history line with a soft fill. `values` are [time, value] pairs, oldest first; the last `span` seconds up to
// `end` span the width, so a short history grows in from the right. A null value breaks the line (the helper
// wasn't sampling). An optional second series draws as a plain line. The owner may append to the arrays in place
// and bump `revision` instead of handing over new ones.
Item {
    id: root
    property var values: []
    property var secondary: []
    property real maximum: 100
    property real span: 60
    property real end: 0
    property int revision: 0
    property color color: Theme.accent
    property color secondaryColor: Theme.activityWatching
    property real lineWidth: 1.5
    clip: true
    // Runs of [x, y] points, newest first. Walks back from the newest point and stops one point past the left edge,
    // so a one-minute graph never looks at the rest of a longer history.
    function segments(series, revision) {
        const runs = [];
        if (!series || !series.length || width <= 0 || span <= 0)
            return runs;
        const start = end - span, scale = width / span, top = Math.max(1e-9, maximum), usable = height - lineWidth;
        let run = [];
        for (let i = series.length - 1; i >= 0; i--) {
            const time = series[i][0], value = series[i][1];
            if (value === null || value === undefined) {
                if (run.length)
                    runs.push(run);
                run = [];
            } else {
                run.push([width - (end - time) * scale, height - lineWidth / 2 - Math.max(0, Math.min(1, value / top)) * usable]);
            }
            if (time < start)
                break;
        }
        if (run.length)
            runs.push(run);
        return runs.filter(points => points.length > 1);
    }
    function line(runs) {
        return runs.map(points => "M " + points.map(p => p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" L ")).join(" ");
    }
    function area(runs) {
        return runs.map(points => "M " + points.map(p => p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" L ")
            + " L " + points[points.length - 1][0].toFixed(1) + " " + height + " L " + points[0][0].toFixed(1) + " " + height + " Z").join(" ");
    }
    readonly property var mainRuns: segments(values, revision)
    readonly property var secondaryRuns: segments(secondary, revision)
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.16)
            PathSvg { path: root.area(root.mainRuns) }
        }
        ShapePath {
            strokeWidth: root.lineWidth
            strokeColor: root.color
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.line(root.mainRuns) }
        }
        ShapePath {
            strokeWidth: root.lineWidth
            strokeColor: root.secondaryRuns.length ? root.secondaryColor : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.line(root.secondaryRuns) }
        }
    }
}
