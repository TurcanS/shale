import QtQuick
import Quickshell.Widgets
import "../core"

// Rounded album cover with a music glyph while the image is missing or loading.
ClippingRectangle {
    id: root
    property string source: ""
    property int glyphSize: Math.max(10, Math.round(width * 0.45))
    readonly property bool ready: cover.status === Image.Ready
    radius: Math.round(width / 5)
    color: Theme.raised
    Icon {
        anchors.centerIn: parent
        visible: !root.ready
        name: "music"
        size: root.glyphSize
        color: Theme.muted
    }
    Image {
        id: cover
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Covers are drawn small; decode at twice the size for HiDPI without holding full images.
        sourceSize.width: root.width * 2
        sourceSize.height: root.height * 2
        opacity: root.ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fast
            }
        }
    }
}
