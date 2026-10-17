import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

PanelWindow {
    id: root
    required property string outputName
    property real reveal: 0
    // How far the old image has faded into the new one.
    property real swap: 0
    property string oldImage: ""
    property string newImage: ""
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-wallpaper-transition"
    WlrLayershell.layer: WlrLayer.Bottom
    mask: Region {}
    visible: reveal > 0 && backdrop.status === Image.Ready && !ShellState.locked
    readonly property size outputSize: screen ? Qt.size(screen.width * screen.devicePixelRatio, screen.height * screen.devicePixelRatio) : Qt.size(0, 0)
    function fileUrl(path) {
        return path ? "file://" + encodeURIComponent(path).replace(/%2F/g, "/") : "";
    }
    Connections {
        target: ShellState
        function onWallpaperChangeChanged() {
            if (ShellState.wallpaperChange.monitor !== root.outputName) return;
            fade.stop();
            crossfade.stop();
            handoff.stop();
            root.reveal = 1;
            root.swap = 0;
            root.newImage = "";
            root.oldImage = ShellState.wallpaperChange.oldPath;
            ready.restart();
        }
        function onWallpaperFinished(success) {
            if (ShellState.wallpaperChange.monitor !== root.outputName) return;
            // The daemon accepts a path before it has drawn it, and a large image can take a moment to decode:
            // fading out now would show its empty surface. The new image fades in here first instead.
            if (!success || !root.visible) {
                fade.restart();
                return;
            }
            root.newImage = ShellState.wallpaperChange.path;
            handoff.restart();
        }
    }
    Image {
        id: incoming
        anchors.fill: parent
        source: root.fileUrl(root.newImage)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: root.outputSize
        opacity: root.reveal
        onStatusChanged: {
            if (status === Image.Ready)
                crossfade.restart();
            else if (status === Image.Error)
                fade.restart();
        }
    }
    Image {
        id: backdrop
        anchors.fill: parent
        source: root.fileUrl(root.oldImage)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // A full-screen image is used once per change; keeping it cached would hold several MB per output.
        cache: false
        // The output's size, not the window's: the window only gets a size once it is visible, and visibility
        // waits for this image, so tying the two together loops.
        sourceSize: root.outputSize
        opacity: root.reveal * (1 - root.swap)
        onStatusChanged: if (status === Image.Ready || status === Image.Error) ready.restart()
    }
    Timer {
        id: ready
        interval: 16
        onTriggered: if (backdrop.status !== Image.Loading) ShellState.commitWallpaper()
    }
    SequentialAnimation {
        id: crossfade
        NumberAnimation {
            target: root
            property: "swap"
            to: 1
            duration: Theme.reduced ? 0 : Theme.lowPower ? 140 : 260
            easing.type: Easing.OutCubic
        }
        // The daemon draws the same image underneath meanwhile; then this window steps aside.
        PauseAnimation { duration: 450 }
        ScriptAction { script: { handoff.stop(); root.reveal = 0; root.oldImage = ""; root.newImage = ""; root.swap = 0; } }
    }
    // If the new image never loads, fade out anyway.
    Timer {
        id: handoff
        interval: 3000
        onTriggered: fade.restart()
    }
    NumberAnimation {
        id: fade
        target: root
        property: "reveal"
        to: 0
        duration: Theme.reduced ? 0 : Theme.lowPower ? 140 : 260
        easing.type: Easing.OutCubic
        // Release the images between changes; the next change loads its own before it starts.
        onFinished: root.release()
    }
    function release() {
        crossfade.stop();
        handoff.stop();
        oldImage = "";
        newImage = "";
        swap = 0;
    }
}
