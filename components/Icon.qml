import QtQuick
import "../core"
import "../core/icons.js" as Icons

// An outline glyph from assets/icons, drawn in any colour. Colour changes swap the image, so don't animate them.
Item {
    id: root
    property string name: "grid"
    property int size: Theme.icon
    property color color: Theme.text
    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    Image {
        anchors.fill: parent
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        source: root.name ? Icons.url(root.name, root.color) : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
