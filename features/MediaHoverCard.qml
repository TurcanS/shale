import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"
import "../components" as C

// Quick controls that open while the pointer rests on the bar's now-playing button.
// Clicking the button still opens the full media page.
PopupWindow {
    id: root
    required property var bar
    required property Item button
    // True while the pointer is on the bar button.
    property bool buttonHovered: false
    readonly property var player: NowPlaying.player
    readonly property bool allowed: !!player && !ShellState.locked && (ShellState.panel === "" || ShellState.screenName !== bar.outputName)
    readonly property bool wanted: allowed && (buttonHovered || cardHover.hovered)
    property bool shown: false
    property real reveal: shown ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.shown ? Theme.enter : Theme.leave
            easing.type: Easing.OutCubic
        }
    }
    onWantedChanged: {
        if (!allowed) {
            openTimer.stop();
            shown = false;
        } else if (wanted) {
            closeTimer.stop();
            if (!shown)
                openTimer.restart();
        } else {
            openTimer.stop();
            closeTimer.restart();
        }
    }
    Timer {
        id: openTimer
        interval: 350
        onTriggered: root.shown = root.wanted
    }
    Timer {
        id: closeTimer
        interval: 250
        onTriggered: root.shown = root.wanted
    }
    // MPRIS does not push position updates; poll while the card is visible.
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && !!root.player && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }
    function time(seconds) {
        if (!isFinite(seconds) || seconds < 0)
            return "0:00";
        return Math.floor(seconds / 60) + ":" + String(Math.floor(seconds % 60)).padStart(2, "0");
    }
    anchor.window: bar
    anchor.item: button
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.rect.width: button.width
    anchor.rect.height: button.height + 10
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    implicitWidth: 320
    implicitHeight: card.implicitHeight
    visible: reveal > 0
    color: "transparent"
    Rectangle {
        id: card
        width: parent.width
        implicitHeight: content.implicitHeight + 28
        radius: Theme.panelRadius
        color: Theme.panel
        border.width: 1
        border.color: Theme.border
        opacity: root.reveal
        transform: Translate { y: Theme.reduced ? 0 : (1 - root.reveal) * -6 }
        HoverHandler {
            id: cardHover
        }
        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                C.CoverArt {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    source: root.player ? root.player.trackArtUrl || "" : ""
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    C.Label {
                        text: root.player ? root.player.trackTitle || "Unknown track" : ""
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: root.player ? root.player.trackArtist || root.player.identity : ""
                        color: Theme.muted
                        font.pixelSize: Theme.small
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
            ColumnLayout {
                visible: !!root.player && root.player.lengthSupported && root.player.positionSupported && root.player.length > 0
                Layout.fillWidth: true
                spacing: 3
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Theme.raised
                    Rectangle {
                        width: root.player && root.player.length > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                        height: parent.height
                        radius: 2
                        color: NowPlaying.artColors[0]
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    C.Label {
                        text: root.player ? root.time(root.player.position) : ""
                        font.family: Theme.mono
                        font.pixelSize: Theme.caption
                        color: Theme.muted
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: root.player ? root.time(root.player.length) : ""
                        font.family: Theme.mono
                        font.pixelSize: Theme.caption
                        color: Theme.muted
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                C.Button {
                    glyph: "previous"
                    flat: true
                    implicitWidth: 38
                    implicitHeight: 38
                    cornerRadius: 19
                    hint: "Previous track"
                    enabled: !!root.player && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                C.Button {
                    glyph: NowPlaying.playing ? "pause" : "play"
                    accent: true
                    implicitWidth: 44
                    implicitHeight: 44
                    cornerRadius: 22
                    hint: NowPlaying.playing ? "Pause" : "Play"
                    enabled: !!root.player && root.player.canTogglePlaying
                    onClicked: root.player.togglePlaying()
                }
                C.Button {
                    glyph: "next"
                    flat: true
                    implicitWidth: 38
                    implicitHeight: 38
                    cornerRadius: 19
                    hint: "Next track"
                    enabled: !!root.player && root.player.canGoNext
                    onClicked: root.player.next()
                }
            }
        }
    }
}
