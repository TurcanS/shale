import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"
import "../components" as C

// Brief "now playing" card when the track changes in the background.
PanelWindow {
    id: trackWindow
    // Whether this window's screen is the one toasts show on now.
    property bool target: false
    property string title: ""
    property string artist: ""
    property bool shown: false
    readonly property var workspace: Services.workspaces.find(w => w.monitor && w.monitor.name === trackWindow.screen.name && w.active)
    readonly property bool allowed: trackWindow.target && !ShellState.locked && ShellState.setting("trackChangeCard", true) && !Focus.digest
        && !(workspace && workspace.hasFullscreen) && !(ShellState.panel === "control" && ShellState.detail === "media")
    property real reveal: shown && allowed ? 1 : 0
    // Lively and Playful: it swings down from its top edge like a cassette door and seats. Calm keeps the drop.
    Behavior on reveal {
        NumberAnimation {
            duration: trackWindow.shown ? (Motion.calm ? Theme.enter : Motion.ms(420)) : Theme.leave
            easing.type: trackWindow.shown && !Motion.calm ? Easing.BezierSpline : Easing.OutCubic
            easing.bezierCurve: Motion.seatCurve(Motion.ov(1.1))
        }
    }
    Connections {
        target: NowPlaying
        function onTrackChanged() {
            const player = NowPlaying.player;
            if (!trackWindow.allowed || !player)
                return;
            trackWindow.title = player.trackTitle || "";
            trackWindow.artist = player.trackArtist || player.identity || "";
            trackWindow.shown = true;
            if (!trackHover.hovered)
                trackTimer.restart();
        }
    }
    Timer {
        id: trackTimer
        interval: 3500
        onTriggered: trackWindow.shown = false
    }
    anchors {
        top: true
    }
    margins.top: ShellState.barBottomOn(trackWindow.screen ? trackWindow.screen.name : "") + 9
    implicitWidth: 340
    implicitHeight: 64
    visible: reveal > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-track"
    WlrLayershell.layer: WlrLayer.Overlay
    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Theme.module
        border.width: 1
        border.color: Theme.cardEdge
        opacity: Math.min(1, trackWindow.reveal * (Motion.calm ? 1 : 3))
        transform: [
            Translate { y: Theme.reduced || !Motion.calm ? 0 : (1 - trackWindow.reveal) * -8 },
            Rotation {
                origin.x: trackWindow.width / 2
                origin.y: 0
                axis { x: 1; y: 0; z: 0 }
                angle: Motion.calm ? 0 : 84 * (1 - trackWindow.reveal)
            }
        ]
        HoverHandler {
            id: trackHover
            // Reading the card keeps it open; leaving gives a moment before it goes.
            onHoveredChanged: if (hovered)
                trackTimer.stop();
            else if (trackWindow.shown)
                trackTimer.restart()
        }
        TapHandler {
            onTapped: {
                trackWindow.shown = false;
                ShellState.open("control", trackWindow.screen.name);
                ShellState.detail = "media";
            }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: Theme.gapM
            C.CoverArt {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: Theme.radiusKey
                source: NowPlaying.artFile
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                C.Label {
                    text: trackWindow.title
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                C.Label {
                    text: trackWindow.artist
                    color: Theme.textMuted
                    font.pixelSize: Theme.small
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            C.Button {
                glyph: "next"
                flat: true
                implicitWidth: 36
                implicitHeight: Theme.controlHeight
                cornerRadius: 18
                hint: "Next track"
                visible: !!NowPlaying.player && NowPlaying.player.canGoNext
                onClicked: NowPlaying.player.next()
            }
        }
    }
}
