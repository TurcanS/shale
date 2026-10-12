import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

PanelWindow {
    id: root
    required property string outputName
    property real reveal: 0
    property string oldImage: ""
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
            if (ShellState.wallpaperChange.monitor === root.outputName)
                fade.restart();
        }
    }
    Image {
        id: backdrop
        anchors.fill: parent
        source: root.oldImage ? "file://" + encodeURIComponent(root.oldImage).replace(/%2F/g, "/") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // A full-screen image is used once per change; keeping it cached would hold several MB per output.
        cache: false
        // The output's size, not the window's: the window only gets a size once it is visible, and visibility
        // waits for this image, so tying the two together loops.
        sourceSize: root.screen ? Qt.size(root.screen.width * root.screen.devicePixelRatio, root.screen.height * root.screen.devicePixelRatio) : Qt.size(0, 0)
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
        // Release the image between changes; the next change loads its own before it starts.
        onFinished: root.oldImage = ""
    }
}
