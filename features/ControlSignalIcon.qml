import QtQuick
import QtQuick.Shapes
import "../core"

Shape {
    id: signalIcon
    property int bars: 4
    property color color: Theme.text
    implicitWidth: 18
    implicitHeight: 18
    preferredRendererType: Shape.CurveRenderer
    ControlSignalArc { d: "M4 9.5a12 12 0 0 1 16 0"; lit: signalIcon.bars >= 4; color: signalIcon.color }
    ControlSignalArc { d: "M7 13a7.5 7.5 0 0 1 10 0"; lit: signalIcon.bars >= 3; color: signalIcon.color }
    ControlSignalArc { d: "M10 16.5a3 3 0 0 1 4 0"; lit: signalIcon.bars >= 2; color: signalIcon.color }
    ControlSignalArc { d: "M12 19.5h.01"; color: signalIcon.color }
}
