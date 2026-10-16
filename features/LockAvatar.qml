import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../core"
import "../components" as C

// Your picture from ~/.face when there is one, otherwise your initial.
Rectangle {
    id: root
    readonly property string user: Quickshell.env("USER") || ""
    readonly property string face: Quickshell.env("HOME") + "/.face"
    property bool hasFace: false
    Process {
        command: ["test", "-r", root.face]
        running: true
        onExited: code => root.hasFace = code === 0
    }
    implicitWidth: 72
    implicitHeight: 72
    radius: width / 2
    color: Theme.selection
    border.width: 2
    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
    C.Label {
        anchors.centerIn: parent
        visible: avatar.status !== Image.Ready
        text: root.user.charAt(0).toUpperCase()
        color: Theme.accentText
        font.pixelSize: Math.round(root.width * 0.42)
        font.weight: Font.Medium
        elide: Text.ElideNone
    }
    Image {
        id: avatar
        anchors.fill: parent
        anchors.margins: 3
        source: root.hasFace ? "file://" + root.face.split("/").map(encodeURIComponent).join("/") : ""
        sourceSize.width: 144
        sourceSize.height: 144
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
