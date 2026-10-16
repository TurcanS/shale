import QtQuick
import QtQuick.Effects
import "../core"

// The lock screen's wallpaper: blurred and dimmed so it keeps the desktop's mood without showing its
// contents. `blur` and `dim` (0–1) let a style ease from the plain wallpaper and back to it.
Item {
    id: root
    property string screenName: ""
    property real blur: 1
    property real dim: 1
    // How far the blurred copy is darkened at full `dim`.
    property real darken: 0.06
    // A full-resolution copy under the blur, so the lock screen can start and end on the desktop's own wallpaper.
    property bool sharp: false
    readonly property string wallpaper: ShellState.activeWallpapers[screenName] || ShellState.activeWallpapers[Object.keys(ShellState.activeWallpapers)[0]] || ""
    readonly property string source: wallpaper ? "file://" + wallpaper.split("/").map(encodeURIComponent).join("/") : ""
    // Ready once the sharp copy can be shown, or straight away when there is nothing to wait for.
    readonly property bool ready: !sharp || source === "" || full.status === Image.Ready || full.status === Image.Error

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.mix(Theme.background, Theme.selection, 0.55) }
            GradientStop { position: 1; color: Theme.background }
        }
    }
    // Cropped like the desktop's wallpaper, so the hand-off lines up.
    Image {
        id: full
        anchors.fill: parent
        visible: root.sharp && status === Image.Ready
        source: root.sharp ? root.source : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(root.width, root.height)
    }
    Image {
        id: backdrop
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Blur hides detail anyway; a small decode keeps memory and the blur pass cheap.
        sourceSize.width: 640
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: backdrop
        visible: backdrop.status === Image.Ready && opacity > 0
        opacity: root.sharp ? Math.min(1, root.blur * 1.4) : 1
        blurEnabled: true
        blurMax: 64
        blur: root.sharp ? 0.35 + 0.65 * root.blur : 1
        saturation: -0.1 * root.dim
        brightness: -root.darken * root.dim
    }
    // Darker at the edges so the clock and the bottom controls stay readable on any wallpaper.
    Rectangle {
        anchors.fill: parent
        opacity: root.dim
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.32) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.1) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }
}
