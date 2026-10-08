import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

PanelWindow {
    id: root
    required property string outputName
    property real reveal: 0
    property string oldImage: ""
    property string nextImage: ""
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-wallpaper-transition"
    WlrLayershell.layer: WlrLayer.Bottom
    mask: Region {}
    visible: reveal > 0 && backdrop.status === Image.Ready && !ShellState.locked
    Connections {
        target: ShellState
        function onWallpaperChangeChanged() {
            if (ShellState.wallpaperChange.monitor !== root.outputName) return;
            fade.stop();
            root.reveal = 1;
            root.oldImage = ShellState.wallpaperChange.oldPath;
            ready.restart();
        }
        function onWallpaperFinished(success) {
            if (ShellState.wallpaperChange.monitor === root.outputName) {
                root.nextImage = success ? ShellState.wallpaperChange.path : root.oldImage;
                fade.restart();
            }
        }
    }
    Image {
        id: backdrop
        anchors.fill: parent
        source: root.oldImage ? "file://" + encodeURIComponent(root.oldImage).replace(/%2F/g, "/") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(root.width * 1, root.height * 1)
        opacity: root.reveal
        onStatusChanged: if (status === Image.Ready || status === Image.Error) ready.restart()
    }
    Timer {
        id: ready
        interval: 16
        onTriggered: if (backdrop.status !== Image.Loading) ShellState.commitWallpaper()
    }
    NumberAnimation {
        id: fade
        target: root
        property: "reveal"
        to: 0
        duration: Theme.reduced ? 0 : Theme.lowPower ? 140 : 260
        easing.type: Easing.OutCubic
        onFinished: root.oldImage = root.nextImage
    }
}
