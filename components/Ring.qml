import QtQuick
import QtQuick.Shapes
import "../core"

// A ring meter: a track and an arc from the top, clockwise for a positive value and anticlockwise for a negative one
// (a pan control). Shares at 36 px with a 4 px stroke; larger for hold progress.
Item {
    id: root
    property int size: 36
    property real thickness: 4
    // -1 … 1 of a full turn, or of `span` degrees when it is set (pan uses ±130°).
    property real value: 0
    property real span: 360
    property color color: Theme.accent
    property color trackColor: Theme.key
    implicitWidth: size
    implicitHeight: size
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.trackColor
            strokeWidth: root.thickness
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (Math.min(root.width, root.height) - root.thickness) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: Math.abs(root.value) > 0.005 ? root.color : "transparent"
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (Math.min(root.width, root.height) - root.thickness) / 2
                radiusY: radiusX
                startAngle: -90
                sweepAngle: Math.max(-1, Math.min(1, root.value)) * root.span
            }
        }
    }
}
