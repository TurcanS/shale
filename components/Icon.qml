import QtQuick
import QtQuick.Shapes
import "../core"
import "../core/icons.js" as Icons

// An outline glyph from assets/icons, drawn as vector paths in any colour. Not an Image: Qt's image loader sends
// data: URLs through its network stack, and every loader thread then sets up TLS.
Item {
    id: root
    property string name: "grid"
    property int size: Theme.icon
    property color color: Theme.text
    readonly property var layers: Icons.shapes[name] || []
    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    component Layer: ShapePath {
        id: layer
        property var source: null
        // Scaled here rather than with an item transform, which clipping ancestors don't always honour.
        scale: Qt.size(root.size / 24, root.size / 24)
        strokeWidth: source ? source.w * root.size / 24 : 0
        strokeColor: source ? Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * source.o) : "transparent"
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: layer.source ? layer.source.d : "" }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // Qt's software renderer draws shapes past their ancestors' clip; a layer is an ordinary texture it clips.
        layer.enabled: GraphicsInfo.api === GraphicsInfo.Software
        Layer { source: root.layers[0] || null }
        Layer { source: root.layers[1] || null }
        Layer { source: root.layers[2] || null }
    }
}
