import QtQuick
import QtQuick.Shapes
import "../core"

// A history line with a soft fill, newest value at the right edge. `capacity` points span the width, so a short
// history grows in from the right instead of stretching. An optional second series draws as a plain line.
Item {
    id: root
    property var values: []
    property var secondary: []
    property real maximum: 100
    property int capacity: 60
    property color color: Theme.accent
    property color secondaryColor: Theme.activityWatching
    property real lineWidth: 1.5
    function points(series) {
        const step = width / Math.max(1, capacity - 1);
        const start = capacity - series.length;
        const top = Math.max(1e-9, maximum);
        return series.map((value, index) => [(start + index) * step, height - lineWidth / 2 - Math.max(0, Math.min(1, value / top)) * (height - lineWidth)]);
    }
    function line(points) {
        return points.length > 1 ? "M " + points.map(p => p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" L ") : "";
    }
    readonly property var mainPoints: points(values)
    readonly property string mainPath: line(mainPoints)
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.16)
            PathSvg {
                path: root.mainPath === "" ? "" : root.mainPath + " L " + root.mainPoints[root.mainPoints.length - 1][0].toFixed(1) + " " + root.height
                    + " L " + root.mainPoints[0][0].toFixed(1) + " " + root.height + " Z"
            }
        }
        ShapePath {
            strokeWidth: root.lineWidth
            strokeColor: root.color
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.mainPath }
        }
        ShapePath {
            strokeWidth: root.lineWidth
            strokeColor: root.secondary.length > 1 ? root.secondaryColor : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.line(root.points(root.secondary)) }
        }
    }
}
