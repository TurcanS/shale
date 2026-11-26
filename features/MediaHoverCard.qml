import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"
import "../components" as C
import "../core/format.js" as Format

// A small Player that opens while the pointer rests on the bar's now-playing button: cover, source, title, a
// position line and the transport. Clicking the button still opens the full Player.
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
        return Format.clock(seconds);
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
        radius: Theme.radiusCase
        color: Theme.caseColor
        border.width: 1
        border.color: Theme.hairline
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
                spacing: Theme.gapM
                C.CoverArt {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: Theme.radiusCard
                    source: NowPlaying.artFile
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            implicitWidth: 6
                            implicitHeight: 6
                            radius: 3
                            color: NowPlaying.playing ? Theme.accent : Theme.textFaint
                        }
                        C.Label {
                            text: root.player ? root.player.identity : ""
                            color: Theme.textDim
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                    }
                    C.Label {
                        text: root.player ? root.player.trackTitle || "Unknown track" : ""
                        font.pixelSize: 15
                        font.weight: 650
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: root.player ? root.player.trackArtist || root.player.identity : ""
                        color: Theme.textMuted
                        font.pixelSize: 13
                        Layout.fillWidth: true
                    }
                }
            }
            ColumnLayout {
                visible: !!root.player && root.player.lengthSupported && root.player.positionSupported && root.player.length > 0
                Layout.fillWidth: true
                spacing: Theme.gapXs
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Theme.key
                    Rectangle {
                        width: root.player && root.player.length > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    C.Label {
                        text: root.player ? root.time(root.player.position) : ""
                        color: Theme.textDim
                        font.pixelSize: 11
                        font.features: ({"tnum": 1})
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: root.player ? root.time(root.player.length) : ""
                        color: Theme.textDim
                        font.pixelSize: 11
                        font.features: ({"tnum": 1})
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.gapM
                TransportKey {
                    glyph: "previous"
                    hint: "Previous track"
                    enabled: !!root.player && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                C.Button {
                    glyph: NowPlaying.playing ? "pause" : "play"
                    accent: true
                    implicitWidth: 42
                    implicitHeight: 42
                    cornerRadius: 21
                    hint: NowPlaying.playing ? "Pause" : "Play"
                    enabled: !!root.player && root.player.canTogglePlaying
                    onClicked: root.player.togglePlaying()
                }
                TransportKey {
                    glyph: "next"
                    hint: "Next track"
                    enabled: !!root.player && root.player.canGoNext
                    onClicked: root.player.next()
                }
            }
        }
    }
    // Previous and next as module keys, like the Player's.
    component TransportKey: C.Button {
        id: key
        implicitWidth: 34
        implicitHeight: 34
        cornerRadius: Theme.radiusKey
        background: Rectangle {
            radius: Theme.radiusKey
            color: key.hovered || key.down || key.visualFocus ? Theme.mix(Theme.module, Theme.text, 0.06) : Theme.module
            opacity: key.enabled ? 1 : Theme.disabledOpacity
            Behavior on color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
            C.Raise {
                shown: key.enabled
                resting: true
                sunk: key.sunk
            }
        }
    }
}
