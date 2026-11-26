import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../core"
import "../components" as C

// Your picture from ~/.face when there is one, otherwise a person on a disc shaded from the accent to its second colour.
Item {
    id: root
    readonly property string face: Quickshell.env("HOME") + "/.face"
    property bool hasFace: false
    Process {
        command: ["test", "-r", root.face]
        running: true
        onExited: code => root.hasFace = code === 0
    }
    implicitWidth: 64
    implicitHeight: 64
    Shape {
        anchors.fill: parent
        visible: avatar.status !== Image.Ready
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: root.width
                y2: root.height
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Theme.second }
            }
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2
                radiusY: root.height / 2
                startAngle: 0
                sweepAngle: 360
            }
        }
    }
    C.Icon {
        anchors.centerIn: parent
        visible: avatar.status !== Image.Ready
        name: "user"
        size: Math.round(root.width * 0.47)
        color: Theme.accentInk
    }
    Image {
        id: avatar
        anchors.fill: parent
        source: root.hasFace ? "file://" + root.face.split("/").map(encodeURIComponent).join("/") : ""
        sourceSize.width: 128
        sourceSize.height: 128
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    MultiEffect {
        anchors.fill: avatar
        source: avatar
        visible: avatar.status === Image.Ready
        maskEnabled: true
        maskSource: avatarMask
    }
    Item {
        id: avatarMask
        width: avatar.width
        height: avatar.height
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: width / 2
        }
    }
}
