import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../core"
import "../services"
import "../components" as C

BarLiveChip {
    id: focusButton
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    shown: Focus.active
    readonly property string remaining: Focus.remainingSeconds < 60 ? Focus.remainingSeconds + "s" : Focus.minutesText(Focus.remainingSeconds)
    hint: "Focus · " + remaining + " left\nClick to end · Scroll to add or take 5 min"
    tooltip: bar.tooltip
    Accessible.name: "Focus, " + remaining + " left"
    onClicked: Focus.end(true)
    WheelHandler {
        property real travelled: 0
        onWheel: event => {
            travelled += event.angleDelta.y;
            const steps = Math.trunc(travelled / 120);
            if (!steps)
                return;
            travelled -= steps * 120;
            Focus.extend(steps > 0 ? 5 : -5);
        }
    }
    contentItem: RowLayout {
        spacing: 6
        // The ring empties as the session runs out.
        Shape {
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.accentLine
                strokeWidth: 2
                fillColor: "transparent"
                PathAngleArc { centerX: 7; centerY: 7; radiusX: 5.5; radiusY: 5.5; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: Theme.accentText
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 7; centerY: 7; radiusX: 5.5; radiusY: 5.5; startAngle: -90; sweepAngle: 360 * Focus.progress }
            }
        }
        C.Label {
            text: focusButton.remaining
            color: Theme.accentText
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.features: ({"tnum": 1})
            elide: Text.ElideNone
        }
    }
}
